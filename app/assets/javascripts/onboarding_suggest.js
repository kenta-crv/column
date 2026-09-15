(function () {
  function dataAttr(el, name) {
    if (!el) return "";
    return el.getAttribute("data-" + name)
      || el.getAttribute("data-" + name.replace(/-/g, "_"))
      || "";
  }

  function closestEl(start, selector) {
    var el = start instanceof Element ? start : start && start.parentElement;
    if (!el || typeof el.closest !== "function") return null;
    return el.closest(selector);
  }

  function showEl(el) {
    if (!el) return;
    el.hidden = false;
    el.removeAttribute("hidden");
    el.style.display = "";
  }

  function hideEl(el) {
    if (!el) return;
    el.hidden = true;
    el.setAttribute("hidden", "hidden");
  }

  function showStatus(el, text, kind) {
    if (!el) return;
    showEl(el);
    el.textContent = text || "";
    el.classList.toggle("is-error", kind === "error");
    el.classList.toggle("is-busy", kind === "busy");
  }

  function requestTitles(btn) {
    if (!btn || btn.getAttribute("data-suggest-busy") === "1") return;

    var keyword1 = document.getElementById("onboarding_keyword1");
    var keyword2 = document.getElementById("onboarding_keyword2");
    var statusEl = document.getElementById("onboarding-suggest-status");
    var listEl = document.getElementById("onboarding-suggestions");
    var titleInput = document.getElementById("onboarding_title");
    var k1 = (keyword1 && keyword1.value ? keyword1.value : "").trim();
    var k2 = (keyword2 && keyword2.value ? keyword2.value : "").trim();
    var failed = dataAttr(btn, "msg-failed");
    var label = dataAttr(btn, "msg-label") || btn.textContent;

    if (!k1 || !k2) {
      showStatus(statusEl, dataAttr(btn, "msg-keywords"), "error");
      return;
    }

    showStatus(statusEl, dataAttr(btn, "msg-suggesting"), "busy");
    hideEl(listEl);
    btn.setAttribute("data-suggest-busy", "1");
    btn.disabled = true;
    btn.textContent = dataAttr(btn, "msg-suggesting") || label;

    var url = dataAttr(btn, "suggest-url") || "/dashboard/start/suggest";
    var params = new URLSearchParams({
      keyword1: k1,
      keyword2: k2,
      language: dataAttr(btn, "language") || "ja"
    });
    var tokenEl = document.querySelector('meta[name="csrf-token"]');

    fetch(url + (url.indexOf("?") >= 0 ? "&" : "?") + params.toString(), {
      method: "GET",
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "X-CSRF-Token": tokenEl ? tokenEl.content : ""
      }
    })
      .then(function (res) {
        return res.json().then(function (data) {
          return { ok: res.ok, data: data || {} };
        }).catch(function () {
          return { ok: false, data: {} };
        });
      })
      .then(function (result) {
        btn.removeAttribute("data-suggest-busy");
        btn.disabled = false;
        btn.textContent = label;
        var data = result.data || {};
        if (!result.ok || !data.success) {
          showStatus(statusEl, data.error || failed, "error");
          return;
        }
        var titles = data.titles || [];
        if (!titles.length) {
          showStatus(statusEl, failed, "error");
          return;
        }
        showStatus(statusEl, dataAttr(btn, "msg-pick"), "busy");
        if (listEl) {
          showEl(listEl);
          listEl.innerHTML = "";
          titles.forEach(function (title) {
            var choice = document.createElement("button");
            choice.type = "button";
            choice.className = "onboarding-suggestion";
            choice.textContent = title;
            choice.addEventListener("click", function () {
              if (titleInput) titleInput.value = title;
            });
            listEl.appendChild(choice);
          });
        }
        if (titleInput && !titleInput.value) titleInput.value = titles[0];
      })
      .catch(function () {
        btn.removeAttribute("data-suggest-busy");
        btn.disabled = false;
        btn.textContent = label;
        showStatus(statusEl, failed, "error");
      });
  }

  window.DrafityOnboardingSuggest = requestTitles;

  document.addEventListener("click", function (e) {
    var btn = closestEl(e.target, "#onboarding-suggest-btn");
    if (!btn) return;
    e.preventDefault();
    requestTitles(btn);
  });
  document.addEventListener("change", function (e) {
    if (!e.target || e.target.name !== "onboarding[generation_mode]") return;
    document.querySelectorAll(".onboarding-mode").forEach(function (label) {
      var radio = label.querySelector('input[type="radio"]');
      label.classList.toggle("is-selected", !!(radio && radio.checked));
    });
  });
})();
