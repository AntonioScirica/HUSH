// Trova i campi di login nella pagina, ci appoggia il tasto Hush, e compila
// utente/password quando l'utente sceglie una voce dal menu.
(function () {
  const seen = new WeakSet()
  let openDropdown = null

  function closeDropdown() {
    if (openDropdown) { openDropdown.remove(); openDropdown = null }
  }

  function usernameFieldFor(passwordField) {
    const form = passwordField.form
    const candidates = form
      ? Array.from(form.querySelectorAll("input"))
      : Array.from(document.querySelectorAll("input"))
    const idx = candidates.indexOf(passwordField)
    for (let i = idx - 1; i >= 0; i--) {
      const el = candidates[i]
      const type = (el.type || "text").toLowerCase()
      if (["text", "email", "tel"].includes(type)) return el
    }
    return null
  }

  function fillReact(el, value) {
    const proto = el.tagName === "TEXTAREA" ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype
    const setter = Object.getOwnPropertyDescriptor(proto, "value").set
    setter.call(el, value)
    el.dispatchEvent(new Event("input", { bubbles: true }))
    el.dispatchEvent(new Event("change", { bubbles: true }))
  }

  function showDropdown(anchor, passwordField, usernameField) {
    closeDropdown()
    const box = document.createElement("div")
    box.className = "hush-dropdown"
    positionNear(box, anchor)
    box.textContent = ""
    const loading = document.createElement("div")
    loading.className = "hush-empty"
    loading.textContent = "Hush · cerco…"
    box.appendChild(loading)
    document.documentElement.appendChild(box)
    openDropdown = box

    browser.runtime.sendMessage({ type: "matches", host: location.hostname }).then((res) => {
      if (openDropdown !== box) return
      box.textContent = ""
      if (!res || res.error) {
        const empty = document.createElement("div")
        empty.className = "hush-empty"
        empty.textContent = res && res.error === "locked"
          ? "Hush è chiuso: apri l'app sul Mac."
          : "Hush non risponde: apri l'app."
        box.appendChild(empty)
        return
      }
      if (!res.entries || res.entries.length === 0) {
        const empty = document.createElement("div")
        empty.className = "hush-empty"
        empty.textContent = "Nessuna voce per questo sito."
        box.appendChild(empty)
        return
      }
      res.entries.forEach((entry) => {
        const row = document.createElement("div")
        row.className = "hush-row"
        const title = document.createElement("span")
        title.className = "hush-title"
        title.textContent = entry.title
        const sub = document.createElement("span")
        sub.className = "hush-sub"
        sub.textContent = [entry.username, entry.projectName].filter(Boolean).join(" · ")
        row.appendChild(title)
        row.appendChild(sub)
        row.addEventListener("click", () => {
          if (usernameField && entry.username) fillReact(usernameField, entry.username)
          fillReact(passwordField, entry.password)
          closeDropdown()
        })
        box.appendChild(row)
      })
    })
  }

  function positionNear(el, anchor) {
    const r = anchor.getBoundingClientRect()
    el.style.position = "absolute"
    el.style.top = window.scrollY + r.bottom + 4 + "px"
    el.style.left = window.scrollX + r.left + "px"
  }

  function attachButton(passwordField) {
    if (seen.has(passwordField)) return
    seen.add(passwordField)

    const button = document.createElement("div")
    button.className = "hush-button"
    button.textContent = "🔒"
    button.title = "Compila con Hush"
    document.documentElement.appendChild(button)

    function reposition() {
      const r = passwordField.getBoundingClientRect()
      if (r.width === 0 && r.height === 0) { button.style.display = "none"; return }
      button.style.display = "flex"
      button.style.top = window.scrollY + r.top + (r.height - 22) / 2 + "px"
      button.style.left = window.scrollX + r.right - 26 + "px"
    }
    reposition()
    window.addEventListener("scroll", reposition, true)
    window.addEventListener("resize", reposition)

    button.addEventListener("mousedown", (e) => {
      e.preventDefault()
      e.stopPropagation()
      const usernameField = usernameFieldFor(passwordField)
      showDropdown(button, passwordField, usernameField)
    })
  }

  function scan() {
    document.querySelectorAll('input[type="password"]').forEach(attachButton)
  }

  document.addEventListener("mousedown", (e) => {
    if (openDropdown && !openDropdown.contains(e.target)) closeDropdown()
  })

  scan()
  new MutationObserver(scan).observe(document.documentElement, { childList: true, subtree: true })
})()
