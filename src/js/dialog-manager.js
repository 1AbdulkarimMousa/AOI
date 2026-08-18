const FOCUSABLE_SELECTOR = 'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

function isVisible(element) {
  if (element.hidden || element.getAttribute("aria-hidden") === "true") return false;
  const style = window.getComputedStyle(element);
  return style.display !== "none" && style.visibility !== "hidden" && element.getClientRects().length > 0;
}

function focusableElements(dialog) {
  return [...dialog.querySelectorAll(FOCUSABLE_SELECTOR)].filter((element) => isVisible(element));
}

export function registerDialogManager() {
  let activeWrappers = [];
  let rootReturnFocus = null;
  let lastNonDialogFocus = document.activeElement;
  const returnFocusByWrapper = new WeakMap();
  const lastFocusByWrapper = new WeakMap();
  const inerted = new Map();

  const restoreInerted = () => {
    for (const [element, wasInert] of inerted) element.inert = wasInert;
    inerted.clear();
  };

  const focusAvailable = (target, wrapper = null) => {
    if (!target?.isConnected || !isVisible(target) || target.closest?.("[inert]")) return false;
    if (wrapper && !wrapper.contains(target)) return false;
    target.focus();
    return document.activeElement === target;
  };

  const focusDialog = (dialog) => {
    const target = focusableElements(dialog)[0] || dialog;
    if (!focusAvailable(target, dialog) && target === dialog && !dialog.hasAttribute("tabindex")) {
      dialog.setAttribute("tabindex", "-1");
      dialog.focus();
    }
  };

  const restore = () => {
    restoreInerted();
    document.documentElement.classList.remove("dialog-open");
    const target = rootReturnFocus;
    rootReturnFocus = null;
    activeWrappers = [];
    focusAvailable(target);
  };

  const sync = () => {
    const dialogs = [...document.querySelectorAll('[role="dialog"]')].filter(isVisible);
    const dialogByWrapper = new Map();
    for (const dialog of dialogs) dialogByWrapper.set(dialog.closest(".modal-backdrop") || dialog, dialog);
    const wrappers = [...dialogByWrapper.keys()];
    const previousWrappers = activeWrappers;
    const previousTop = previousWrappers.at(-1);
    const wrapper = wrappers.at(-1);
    if (!wrapper) {
      if (previousWrappers.length) restore();
      return;
    }

    const activeElement = document.activeElement;
    if (!previousWrappers.length) {
      rootReturnFocus = wrapper.contains(activeElement) ? lastNonDialogFocus : activeElement;
    }
    for (const candidate of wrappers) {
      if (previousWrappers.includes(candidate)) continue;
      const target = previousTop
        ? (previousTop.contains(activeElement) ? activeElement : lastFocusByWrapper.get(previousTop))
        : rootReturnFocus;
      returnFocusByWrapper.set(candidate, target);
    }

    restoreInerted();
    for (const dialog of dialogs) dialog.setAttribute("aria-modal", "true");
    document.documentElement.classList.add("dialog-open");

    let branch = wrapper;
    while (branch.parentElement && branch !== document.body) {
      const parent = branch.parentElement;
      for (const sibling of parent.children) {
        if (sibling === branch || inerted.has(sibling)) continue;
        inerted.set(sibling, sibling.inert);
        sibling.inert = true;
      }
      branch = parent;
    }

    activeWrappers = wrappers;
    if (wrapper === previousTop) return;
    const dialog = dialogByWrapper.get(wrapper);
    if (previousWrappers.includes(wrapper)) {
      const target = returnFocusByWrapper.get(previousTop) || lastFocusByWrapper.get(wrapper);
      if (!focusAvailable(target, wrapper)) focusDialog(dialog);
    } else if (!wrapper.contains(document.activeElement) || document.activeElement.closest?.("[inert]")) {
      focusDialog(dialog);
    }
  };

  const onFocusIn = (event) => {
    const dialog = event.target.closest?.('[role="dialog"]');
    if (!dialog || !isVisible(dialog)) {
      lastNonDialogFocus = event.target;
      return;
    }
    const wrapper = dialog.closest(".modal-backdrop") || dialog;
    lastFocusByWrapper.set(wrapper, event.target);
  };

  const onKeydown = (event) => {
    const dialog = [...document.querySelectorAll('[role="dialog"]')].filter(isVisible).at(-1);
    if (!dialog) return;

    if (event.key === "Escape") {
      const close = dialog.querySelector('[data-dialog-close], button[aria-label*="close" i]');
      if (close) {
        event.preventDefault();
        close.click();
      }
      return;
    }
    if (event.key !== "Tab") return;

    const controls = focusableElements(dialog);
    if (!controls.length) {
      event.preventDefault();
      dialog.focus();
      return;
    }
    const first = controls[0];
    const last = controls.at(-1);
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  };

  const observer = new window.MutationObserver(sync);
  observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["aria-hidden", "class", "hidden", "style"] });
  document.addEventListener("keydown", onKeydown, true);
  document.addEventListener("focusin", onFocusIn, true);
  sync();

  return () => {
    observer.disconnect();
    document.removeEventListener("keydown", onKeydown, true);
    document.removeEventListener("focusin", onFocusIn, true);
    if (activeWrappers.length) restore();
  };
}
