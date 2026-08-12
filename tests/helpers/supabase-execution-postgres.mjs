import { mkdtemp, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const workspace = resolve(import.meta.dirname, '..', '..');
const migrationsDirectory = join(workspace, 'supabase', 'migrations');

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: workspace,
    encoding: 'utf8',
    env: { ...process.env, ...options.env },
    maxBuffer: 20 * 1024 * 1024,
  });
  if (result.status !== 0 && !options.allowFailure) {
    const detail = [result.stdout, result.stderr].filter(Boolean).join('\n').trim();
    throw new Error(`${command} ${args.join(' ')} failed (${result.status})\n${detail}`);
  }
  return result;
}

export async function withDisposablePostgres(callback) {
  const root = await mkdtemp(join(tmpdir(), 'aoi-supabase-execution-'));
  const dataDirectory = join(root, 'data');
  const socketDirectory = join(root, 'socket');
  const port = 20000 + Math.floor(Math.random() * 20000);
  let started = false;

  try {
    run('initdb', ['--auth=trust', '--encoding=UTF8', '--no-locale', '-D', dataDirectory]);
    run('mkdir', ['-p', socketDirectory]);
    run('pg_ctl', [
      '-D', dataDirectory,
      '-o', `-F -k ${socketDirectory} -p ${port}`,
      '-l', join(root, 'postgres.log'),
      '-w', 'start',
    ]);
    started = true;

    const psql = (sql, options = {}) => run('psql', [
      '-X', '--no-psqlrc', '--set', 'ON_ERROR_STOP=1',
      '--host', socketDirectory, '--port', String(port), '--dbname', 'postgres',
      ...(options.file ? ['--file', options.file] : ['--command', sql]),
    ], {
      allowFailure: options.allowFailure,
      env: sessionEnvironment(options),
    });

    psql(`
      create role anon nologin;
      create role authenticated nologin;
      create role service_role nologin bypassrls;
      create schema auth;
      create schema extensions;
      create schema realtime;
      create schema storage;
      create extension pgcrypto with schema extensions;

      create table auth.users (
        id uuid primary key,
        email_confirmed_at timestamptz
      );
      create function auth.uid() returns uuid language sql stable
      set search_path = '' as $$
        select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
      $$;
      create function auth.jwt() returns jsonb language sql stable
      set search_path = '' as $$
        select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb)
      $$;
      grant usage on schema auth to anon, authenticated, service_role;
      grant execute on function auth.uid(), auth.jwt() to anon, authenticated, service_role;

      create table realtime.messages (
        id uuid primary key default extensions.gen_random_uuid(),
        extension text not null
      );
      alter table realtime.messages enable row level security;
      create function realtime.topic() returns text language sql stable
      set search_path = '' as $$
        select current_setting('realtime.topic', true)
      $$;

      create table storage.buckets (
        id text primary key,
        name text not null unique,
        public boolean not null default false,
        file_size_limit bigint,
        allowed_mime_types text[]
      );
      create table storage.objects (
        id uuid primary key default extensions.gen_random_uuid(),
        bucket_id text not null references storage.buckets(id),
        name text not null,
        owner_id text
      );
      alter table storage.objects enable row level security;
      create function storage.foldername(name text) returns text[] language sql immutable
      set search_path = '' as $$
        select case when name is null then null else string_to_array(trim(both '/' from name), '/') end
      $$;
      create function storage.extension(name text) returns text language sql immutable
      set search_path = '' as $$
        select nullif(reverse(split_part(reverse(name), '.', 1)), name)
      $$;
    `);

    await callback({
      psql,
      async applyMigrations(options = {}) {
        const migrations = (await readdir(migrationsDirectory))
          .filter((name) => name.endsWith('.sql'))
          .sort();
        for (const migration of migrations) {
          await options.beforeMigration?.(migration);
          const result = psql('', {
            file: join(migrationsDirectory, migration),
            allowFailure: true,
          });
          if (result.status !== 0) {
            const detail = [result.stdout, result.stderr].filter(Boolean).join('\n').trim();
            throw new Error(`migration ${migration} failed\n${detail}`);
          }
          if (migration === '202608030002_auth_admin_workflows.sql') {
            psql(`
              insert into auth.users (id, email_confirmed_at)
              values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', now());
              insert into public.profiles (id, display_name, login_identifier, status)
              values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Migration Test Admin', 'migration-admin', 'active');
              insert into public.organization_memberships (organization_id, user_id, role, status)
              values (
                '11111111-1111-4111-8111-111111111111',
                'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                'admin',
                'active'
              );
            `);
          }
        }
        return migrations;
      },
      query(sql, options = {}) {
        const result = psql(`copy (${sql}) to stdout with (format csv, header false, null '<null>');`, options);
        return result.stdout.trim();
      },
      execute(sql, options = {}) {
        return psql(sql, options);
      },
      async functionDefinition(signature) {
        const escaped = signature.replaceAll("'", "''");
        return readFileFromCopy(psql(`copy (
          select pg_get_functiondef('${escaped}'::regprocedure)
        ) to stdout;`).stdout);
      },
    });
  } finally {
    if (started) {
      run('pg_ctl', ['-D', dataDirectory, '-m', 'immediate', '-w', 'stop'], { allowFailure: true });
    }
    await rm(root, { recursive: true, force: true });
  }
}

function readFileFromCopy(output) {
  return output.replaceAll('\\n', '\n').replaceAll('\\t', '\t').trim();
}

function sessionEnvironment(options) {
  const settings = [];
  if (options.role) settings.push(`-c role=${options.role}`);
  if (options.actor) settings.push(`-c request.jwt.claim.sub=${options.actor}`);
  return settings.length > 0 ? { PGOPTIONS: settings.join(' ') } : {};
}
