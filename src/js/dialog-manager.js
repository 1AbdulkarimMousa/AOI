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
  let activeWrapper = null;
  let returnFocus = null;
  const inerted = new Map();

  const restore = () => {
    for (const [element, wasInert] of inerted) element.inert = wasInert;
    inerted.clear();
    document.documentElement.classList.remove("dialog-open");
    const target = returnFocus;
    returnFocus = null;
    activeWrapper = null;
    target?.focus?.();
  };

  const sync = () => {
    const dialog = [...document.querySelectorAll('[role="dialog"]')].filter(isVisible).at(-1);
    if (!dialog) {
      if (activeWrapper) restore();
      return;
    }

    const wrapper = dialog.closest(".modal-backdrop") || dialog;
    if (wrapper !== activeWrapper) {
      if (activeWrapper) restore();
      activeWrapper = wrapper;
      returnFocus = document.activeElement;
    }
    dialog.setAttribute("aria-modal", "true");
    document.documentElement.classList.add("dialog-open");

    const parent = wrapper.parentElement;
    if (parent) {
      for (const sibling of parent.children) {
        if (sibling === wrapper || inerted.has(sibling)) continue;
        inerted.set(sibling, sibling.inert);
        sibling.inert = true;
      }
    }
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
  sync();

  return () => {
    observer.disconnect();
    document.removeEventListener("keydown", onKeydown, true);
    if (activeWrapper) restore();
  };
}
