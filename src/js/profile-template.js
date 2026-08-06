export const profileTemplate = String.raw`
<div x-show="profileOpen" class="profile-backdrop" @mousedown.self="closeProfileEditor()">
  <aside class="profile-drawer" role="dialog" aria-modal="true" :aria-label="t('editProfile')" @keydown.tab="trapProfileFocus($event)">
    <header><div><span class="eyebrow" x-text="t('yourAccount')"></span><h2 x-text="t('editProfile')"></h2></div><button class="icon-button" @click="closeProfileEditor()" :aria-label="t('close')">×</button></header>
    <div class="profile-drawer-scroll">
      <section class="profile-identity-editor">
        <span :class="avatarClass(profilePreviewPerson(),'xl')" :style="profilePhotoPreview ? 'background-image:url('+profilePhotoPreview+')' : avatarStyle(profilePreviewPerson())" x-text="profilePhotoPreview ? '' : avatarText(profilePreviewPerson())"></span>
        <div><strong x-text="profileDraft.displayName || access.displayName"></strong><small x-text="profileDraft.jobTitle || (access.role==='admin' ? 'Administrator' : 'Intern')"></small><div><label class="button button-primary profile-upload"><input type="file" accept="image/jpeg,image/png,image/webp" @change="selectProfilePhoto($event)"><span x-text="t('uploadPhoto')"></span></label><button class="button button-secondary" type="button" @click="removeProfilePhoto()" x-text="t('removePhoto')"></button></div></div>
      </section>
      <section class="profile-presets"><label x-text="t('presetAvatar')"></label><div><template x-for="key in avatarKeys" :key="key"><button type="button" class="avatar avatar-md" :class="['avatar-preset-'+key,profileDraft.avatarKey===key && !profileDraft.avatarPath && !profilePhotoFile ? 'selected':'']" @click="choosePresetAvatar(key)" x-text="initials(profileDraft.displayName)"></button></template></div></section>
      <form class="profile-form" @submit.prevent="saveProfile()">
        <label><span x-text="t('displayName')"></span><input x-model="profileDraft.displayName" minlength="2" maxlength="80" required></label>
        <label><span x-text="t('jobTitle')"></span><input x-model="profileDraft.jobTitle" maxlength="100"></label>
        <label class="profile-field-wide"><span x-text="t('shortBio')"></span><textarea x-model="profileDraft.bio" maxlength="240" rows="4"></textarea><small x-text="profileDraft.bio.length+'/240'"></small></label>
        <label><span x-text="t('phone')"></span><input type="tel" x-model="profileDraft.phone" maxlength="40"></label>
        <label><span x-text="t('timezone')"></span><input x-model="profileDraft.timezone" list="aoi-timezones" required><datalist id="aoi-timezones"><option value="UTC"></option><option value="America/New_York"></option><option value="America/Chicago"></option><option value="America/Los_Angeles"></option><option value="Asia/Shanghai"></option><option value="Asia/Dubai"></option><option value="Africa/Cairo"></option><option value="Europe/London"></option></datalist></label>
        <label class="profile-field-wide"><span x-text="t('preferredLanguage')"></span><select x-model="profileDraft.locale"><option value="en">English</option><option value="zh-CN">简体中文</option></select></label>
      </form>
      <div x-show="profileNotice" class="admin-notice" :class="profileNotice?.tone" role="status" x-text="profileNotice?.text"></div>
    </div>
    <footer><button class="button button-secondary" @click="closeProfileEditor()" x-text="t('close')"></button><button class="button button-primary" :disabled="profileSaving" @click="saveProfile()" x-text="profileSaving ? t('saving') : t('saveProfile')"></button></footer>
  </aside>
</div>`;
