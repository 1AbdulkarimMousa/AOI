import {
  createAvatarSignedUrls,
  loadMemberProfile,
  removeAvatarObject,
  updateProfile,
  uploadAvatar,
} from "./api.js";
import { initials, readableError } from "./core.js";

export const AVATAR_KEYS = ["coral", "teal", "blue", "purple", "gold", "slate", "rose", "sand"];

function validTimezone(value) {
  try {
    new Intl.DateTimeFormat("en", { timeZone: value }).format();
    return true;
  } catch {
    return false;
  }
}

export function validateProfile(input = {}) {
  const value = {
    displayName: String(input.displayName || "").trim(),
    jobTitle: String(input.jobTitle || "").trim(),
    bio: String(input.bio || "").trim(),
    phone: String(input.phone || "").trim(),
    timezone: String(input.timezone || "UTC").trim() || "UTC",
    locale: String(input.locale || "en").trim(),
    avatarKey: String(input.avatarKey || "").trim() || null,
    avatarPath: String(input.avatarPath || "").trim() || null,
  };
  const errorKeys = [];
  if (value.displayName.length < 2 || value.displayName.length > 80) errorKeys.push("profileNameInvalid");
  if (value.jobTitle.length > 100) errorKeys.push("profileJobTitleInvalid");
  if (value.bio.length > 240) errorKeys.push("profileBioInvalid");
  if (value.phone.length > 40) errorKeys.push("profilePhoneInvalid");
  if (!validTimezone(value.timezone)) errorKeys.push("profileTimezoneInvalid");
  if (!["en", "zh-CN"].includes(value.locale)) errorKeys.push("profileLocaleInvalid");
  if (value.avatarKey && !AVATAR_KEYS.includes(value.avatarKey)) errorKeys.push("profileAvatarInvalid");
  return { valid: errorKeys.length === 0, value, errorKeys };
}

export function validateAvatarFile(file) {
  if (!file || !["image/jpeg", "image/png", "image/webp"].includes(file.type)) {
    return { valid: false, reasonKey: "profilePhotoTypeInvalid" };
  }
  if (file.size < 1 || file.size > 3 * 1024 * 1024) {
    return { valid: false, reasonKey: "profilePhotoTooLarge" };
  }
  return { valid: true };
}

export function resolveAvatar(person = {}) {
  if (person.avatarUrl) return { kind: "photo", value: person.avatarUrl };
  if (AVATAR_KEYS.includes(person.avatarKey)) return { kind: "preset", value: person.avatarKey };
  return { kind: "initials", value: initials(person.displayName) };
}

export async function reconcileUploadedAvatar(uploadedPath, userId, loadProfile = loadMemberProfile) {
  try {
    const profile = await loadProfile(userId);
    return { resolved: true, profile: profile?.avatarPath === uploadedPath ? profile : null };
  } catch {
    return { resolved: false, profile: null };
  }
}

export function createProfileState() {
  return {
    accountMenuOpen: false,
    profileOpen: false,
    profileSaving: false,
    profileNotice: null,
    profilePhotoFile: null,
    profilePhotoPreview: "",
    profileReturnFocus: null,
    profileDraft: {
      displayName: "", jobTitle: "", bio: "", phone: "", timezone: "UTC",
      locale: "en", avatarKey: null, avatarPath: null,
    },
    avatarKeys: AVATAR_KEYS,

    avatarText(person) {
      return resolveAvatar(person).kind === "photo" ? "" : initials(person?.displayName);
    },
    avatarClass(person, size = "md") {
      const avatar = resolveAvatar(person);
      return `avatar avatar-${size} ${avatar.kind === "preset" ? `avatar-preset-${avatar.value}` : ""}`.trim();
    },
    avatarStyle(person) {
      const avatar = resolveAvatar(person);
      return avatar.kind === "photo" ? `background-image:url(${JSON.stringify(avatar.value).slice(1, -1)})` : "";
    },
    openProfileEditor() {
      this.profileReturnFocus = document.activeElement;
      this.accountMenuOpen = false;
      this.profileNotice = null;
      this.profilePhotoFile = null;
      if (this.profilePhotoPreview) URL.revokeObjectURL(this.profilePhotoPreview);
      this.profilePhotoPreview = "";
      this.profileDraft = {
        displayName: this.access?.displayName || "",
        jobTitle: this.access?.jobTitle || "",
        bio: this.access?.bio || "",
        phone: this.access?.phone || "",
        timezone: this.access?.timezone || "UTC",
        locale: this.access?.locale || this.locale || "en",
        avatarKey: this.access?.avatarKey || null,
        avatarPath: this.access?.avatarPath || null,
      };
      this.profileOpen = true;
      this.$nextTick(() => document.querySelector(".profile-drawer input")?.focus());
    },
    closeProfileEditor() {
      this.profileOpen = false;
      this.profilePhotoFile = null;
      if (this.profilePhotoPreview) URL.revokeObjectURL(this.profilePhotoPreview);
      this.profilePhotoPreview = "";
      this.$nextTick(() => this.profileReturnFocus?.focus?.());
    },
    trapProfileFocus(event) {
      const drawer = document.querySelector(".profile-drawer");
      if (!drawer) return;
      const controls = [...drawer.querySelectorAll('button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])')]
        .filter((element) => element.offsetParent !== null);
      if (!controls.length) return;
      const first = controls[0];
      const last = controls.at(-1);
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    },
    choosePresetAvatar(key) {
      if (!AVATAR_KEYS.includes(key)) return;
      this.profileDraft.avatarKey = key;
      this.profileDraft.avatarPath = null;
      this.profilePhotoFile = null;
      if (this.profilePhotoPreview) URL.revokeObjectURL(this.profilePhotoPreview);
      this.profilePhotoPreview = "";
    },
    removeProfilePhoto() {
      this.profileDraft.avatarPath = null;
      this.profilePhotoFile = null;
      if (this.profilePhotoPreview) URL.revokeObjectURL(this.profilePhotoPreview);
      this.profilePhotoPreview = "";
    },
    selectProfilePhoto(event) {
      const file = event.target.files?.[0];
      event.target.value = "";
      const check = validateAvatarFile(file);
      if (!check.valid) {
        this.profileNotice = { tone: "error", text: this.t(check.reasonKey) };
        return;
      }
      if (this.profilePhotoPreview) URL.revokeObjectURL(this.profilePhotoPreview);
      this.profilePhotoFile = file;
      this.profilePhotoPreview = URL.createObjectURL(file);
      this.profileDraft.avatarKey = null;
      this.profileNotice = null;
    },
    profilePreviewPerson() {
      return {
        ...this.profileDraft,
        avatarUrl: this.profilePhotoPreview || (this.profileDraft.avatarPath === this.access?.avatarPath ? this.access?.avatarUrl : ""),
      };
    },
    async saveProfile() {
      const validated = validateProfile(this.profileDraft);
      if (!validated.valid) {
        this.profileNotice = { tone: "error", text: this.t(validated.errorKeys[0]) };
        return;
      }
      if (this.preview) {
        this.profileNotice = { tone: "warning", text: this.t("previewProfileDisabled") };
        return;
      }
      this.profileSaving = true;
      this.profileNotice = null;
      const previousPath = this.access?.avatarPath || null;
      let uploadedPath = null;
      try {
        const payload = { ...validated.value };
        if (this.profilePhotoFile) {
          const uploaded = await uploadAvatar(this.profilePhotoFile, this.access.organizationId, this.access.userId);
          uploadedPath = uploaded.objectPath;
          payload.avatarPath = uploadedPath;
          payload.avatarKey = null;
        }
        let saved;
        try {
          saved = await updateProfile(payload);
        } catch (reason) {
          if (!uploadedPath) throw reason;
          const outcome = await reconcileUploadedAvatar(uploadedPath, this.access.userId);
          if (!outcome.profile) {
            if (outcome.resolved) await removeAvatarObject(uploadedPath).catch(() => {});
            throw reason;
          }
          saved = outcome.profile;
        }
        const urls = await createAvatarSignedUrls(saved.avatarPath ? [saved.avatarPath] : []).catch(() => ({}));
        this.access = { ...this.access, ...saved, avatarUrl: urls[saved.avatarPath] || "" };
        this.locale = saved.locale;
        localStorage.setItem("aoi-locale", saved.locale);
        document.documentElement.lang = saved.locale;
        this.chatMembers = (this.chatMembers || []).map((member) => member.userId === saved.userId ? { ...member, ...saved, avatarUrl: urls[saved.avatarPath] || "" } : member);
        if (previousPath && previousPath !== saved.avatarPath) await removeAvatarObject(previousPath).catch(() => {});
        if (this.chatChannel) await this.chatChannel.send({ type: "broadcast", event: "profile-changed", payload: { userId: saved.userId } });
        this.closeProfileEditor();
        this.showToast(this.t("profileSaved"), this.t("profileSavedCopy"));
      } catch (reason) {
        this.profileNotice = { tone: "error", text: readableError(reason, this.t("saveProfileFailed")) };
      } finally {
        this.profileSaving = false;
      }
    },
  };
}
