# Kayla User And Work Seed Design

## Goal

Create or reuse Kayla Tillmon's AOI intern account and seed the professional-side PMF planning work supplied on August 4, 2026. The seed must be repeatable and must not misrepresent plans, hypotheses, or interview questions as collected evidence.

## Account

- Login email: `ktillmon@smith.edu`
- Display name: `Kayla Tillmon`
- Organization role: `intern`
- Final profile and membership status: `disabled`
- Initial password: supplied out of band during execution and never stored in source control
- Auth state: sign-in banned after the historical seed is complete
- Existing-account behavior: reuse the matching Auth user and repair missing profile or membership rows rather than creating a duplicate
- Withdrawal effective at: August 4, 2026 at 2:19 AM America/New_York, based on the supplied email timestamp

## Seeded Work

The seed creates or updates eight Kayla-owned project tasks. Completed and submitted artifacts retain their historical state; unfinished work is cancelled because Kayla withdrew effective immediately.

1. **Standardize professional segments and recruitment criteria**
   - Status: `completed`
   - Progress: 100%
   - Captures the five professional profiles, their Layer 1 care contexts, secondary attributes, qualification criteria, and unresolved classification decisions.
2. **Finalize dental professional interview guide**
   - Status: `submitted`
   - Progress: 100%
   - Captures the common interview flow, H1-H5 alignment, segment-specific probes, and clinical, AI, privacy, and recommendation boundaries.
3. **Execute Layer 1 professional recruitment pipeline**
   - Status: `cancelled`
   - Progress reflects planning completion rather than completed recruitment.
   - Captures the 31-35 professional target, segment allocations, qualification flow, and open recruitment decisions.

The additional cancelled tasks cover Layer 1 hypothesis maintenance, alignment with Wen, competitor baseline and pricing research, competitor review mining, and the Friday cross-evidence synthesis. Each task stores source-derived measurable requirements in its objective and acceptance criteria. Stable seed markers make task upserts idempotent.

## Historical EOD Briefs

The July 29, July 30, and July 31 updates are imported as historical submitted EOD briefs. They preserve the supplied outcomes, blockers, priorities, and on-track status.

The supplied evidence references say only `OneDrive` or identify Kayla's OneDrive folder without a URL. The seed records that the URL was not provided and leaves `evidence_links` empty rather than inventing a link. Inferred submission timestamps use the standard 5:00 PM EOD due time and carry an explicit historical-import note stating that the exact submission time is unavailable.

## PMF Reference Data

The final professional standardization framework is canonical. The seed upserts these professional research segments:

- Pediatric Dentist - Family/Caregiver-Supported Care
- Orthodontist - Long-Term Treatment Monitoring
- Periodontist - Periodontal/Implant Maintenance
- General Dentist - High-Value Restorative/Cosmetic Care
- Dental Hygienist - Preventive Education and Home-Care Behavior

Descriptions capture the relevant care context and recruitment basis. Existing segment codes remain stable so references are not broken.

The professional recruitment target remains 31-35, allocated as:

- Pediatric dentists: 8
- Orthodontists: 8
- Periodontists / implant-maintenance professionals: 5-6, planned as 6
- General dentists with high-value restorative/cosmetic focus: 4-5, planned as 5
- Dental hygienists: 6-8, planned as 7

The seed does not claim that any target has been recruited or interviewed.

## Evidence Boundary

The supplied documents contain research plans, interview prompts, hypotheses, and recruitment criteria. They are not respondent data. The seed must not create:

- Respondents or contact records
- Consent records
- Research sessions
- Evidence records or quotations
- PMF observations
- Product events
- Value-exchange observations
- Gate approvals

This prevents planned questions and working assumptions from entering approved-only analysis as factual findings.

## Implementation

A repository operator script uses the Supabase service-role credential from the local environment. It performs these steps:

1. Find Kayla by normalized email or create her with Supabase Admin Auth.
2. Set the supplied temporary password without persisting it in the repository.
3. Upsert the profile and AOI intern membership as active temporarily so assignment-integrity triggers accept the historical rows.
4. Resolve the active `AOI-PMF-01` project.
5. Upsert the five professional segment definitions by project and stable segment code.
6. Upsert the eight tasks by project and stable seed marker.
7. Upsert the three historical EOD briefs by project, author, and date.
8. Upsert the withdrawal activity event without duplication.
9. Update the professional sample target without changing evidence-derived actual counts.
10. Disable the organization membership and profile, then ban Auth sign-in.
11. Return a redacted result summary.

The script fails before project-data writes if the organization or project cannot be resolved. It does not print the service-role credential.

## Verification

Automated tests validate:

- Account and role constants
- The eight task statuses and ownership
- The three historical EOD dates and source-link boundary
- The withdrawal lifecycle and activity event
- The five canonical professional segment definitions
- Recruitment allocation totals of 31 minimum, 35 maximum, and 34 planned
- Absence of respondent, session, evidence, observation, and approval payloads
- Stable identifiers needed for idempotent upserts

After execution, direct read-back verifies:

- One Auth user exists for Kayla's normalized email
- Kayla's profile and intern membership are disabled and Auth is banned
- Kayla owns exactly the eight seeded tasks, with unfinished work cancelled
- Exactly three historical EOD briefs exist for July 29-31
- The five professional segments have the canonical names and descriptions
- No research evidence rows were created by the seed

## Scope

This change seeds Kayla's account and supplied planning work only. It does not redesign the PMF interface, import PDF files, infer interview results, approve Kayla's submitted work, or alter unrelated users and records.
