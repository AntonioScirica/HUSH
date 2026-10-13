// Trova i campi di login nella pagina e compila utente/password quando
// l'utente sceglie una voce dal menu, che compare da sé sopra il campo
// appena lo tocchi — niente lucchetto da cliccare.
(function () {
  const seen = new WeakSet()
  let openDropdown = null
  let openField = null

  function closeDropdown() {
    if (openDropdown) { openDropdown.remove(); openDropdown = null }
    openField = null
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

  // Login in due schermi (Google, X…): scelta la voce sul campo email,
  // quando arriva il campo password (pagina nuova, ma stessa origine —
  // sessionStorage sopravvive da sola al cambio pagina) si riempie subito
  // senza rimostrare il menu. 3 minuti di validità: oltre, meglio chiedere
  // di nuovo che riempire alla cieca una pagina magari tutta diversa.
  const CHIAVE_SCELTA = "hushUltimaScelta"
  const VALIDITA_MS = 3 * 60 * 1000

  function ricordaScelta(entry) {
    try {
      sessionStorage.setItem(CHIAVE_SCELTA, JSON.stringify({
        title: entry.title, username: entry.username, ts: Date.now(),
      }))
    } catch {} // storage negato (iframe di terze parti ecc.): pazienza
  }

  function sceltaRecente(entries) {
    let salvata
    try { salvata = JSON.parse(sessionStorage.getItem(CHIAVE_SCELTA) || "null") } catch { return null }
    if (!salvata || Date.now() - salvata.ts > VALIDITA_MS) return null
    return entries.find((e) => e.title === salvata.title && e.username === salvata.username) || null
  }

  /// Un solo indizio, non una ricerca a tappeto: legge il testo GIÀ visibile
  /// (lo switcher account di Google scrive l'email per esteso da qualche
  /// parte nella pagina) e vede se combacia con l'utente di UNA sola voce —
  /// con due voci diverse candidate è meglio non indovinare e mostrare il
  /// menu come sempre.
  function suggeritaDallaPagina(entries) {
    const testo = document.body.innerText.toLowerCase()
    const combacianti = entries.filter((e) => e.username && testo.includes(e.username.toLowerCase()))
    return combacianti.length === 1 ? combacianti[0] : null
  }

  function fillReact(el, value) {
    const proto = el.tagName === "TEXTAREA" ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype
    const setter = Object.getOwnPropertyDescriptor(proto, "value").set
    setter.call(el, value)
    el.dispatchEvent(new Event("input", { bubbles: true }))
    el.dispatchEvent(new Event("change", { bubbles: true }))
  }

  function positionAbove(box, field) {
    const r = field.getBoundingClientRect()
    box.style.left = window.scrollX + r.left + "px"
    box.style.width = r.width + "px"
    // Di default sopra il campo, attaccato: solo se sopra non c'entra
    // (campo vicino al bordo della pagina) si mette sotto.
    const sopra = r.top - box.offsetHeight - 4
    box.style.top = window.scrollY + (sopra >= 0 ? sopra : r.bottom + 4) + "px"
  }

  function showDropdown(field, passwordField, usernameField) {
    closeDropdown()
    // Niente da mostrare finché non si sa se c'è qualcosa da riempire: il
    // box non tocca il DOM finché non ci sono davvero voci, altrimenti si
    // vede comparire e sparire da solo ("cerco…" seguito subito dal nulla).
    const box = document.createElement("div")
    box.className = "hush-dropdown"
    box.style.position = "absolute"
    openField = field

    // Dopo un aggiornamento dell'estensione le pagine già aperte tengono il
    // vecchio script col canale morto: senza catch resterebbe appesa per sempre.
    Promise.resolve()
      .then(() => chrome.runtime.sendMessage({ type: "matches", host: location.hostname }))
      .catch(() => ({ error: "ricarica" }))
      .then((res) => {
      if (openField !== field) return // il campo è cambiato o si è chiuso nel frattempo
      if (!res || res.error) return
      // Campo solo-email (password in un altro schermo): senza username
      // salvato non c'è nulla da riempire qui, inutile mostrare la voce.
      const entries = (res.entries || []).filter((e) => passwordField || e.username)
      if (entries.length === 0) return

      // Il passo prima (campo email) aveva già scelto: qui si riempie e
      // basta, niente menu da rimostrare.
      if (passwordField === field) {
        const scelta = sceltaRecente(entries)
        if (scelta) {
          fillReact(passwordField, scelta.password)
          sessionStorage.removeItem(CHIAVE_SCELTA)
          return
        }
        // Nessuna scelta nostra da ricordare: capita quando l'account lo ha
        // già scelto il sistema (lo switcher account di Google, per dire) e
        // il campo email/utente non è mai passato da qui. Se la pagina
        // mostra da qualche parte l'email di una voce sola, è ragionevole
        // riempire subito invece di rimandare a menu e ricerca.
        const suggerita = suggeritaDallaPagina(entries)
        if (suggerita) {
          fillReact(passwordField, suggerita.password)
          return
        }
      }

      // Riga condivisa: usata sia per le voci del sito corrente sia per i
      // risultati della ricerca su tutto il caveau, qualche riga più sotto.
      function creaRiga(entry, container) {
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
        // mousedown, non click: il click arriva dopo il blur del campo e
        // certi siti nel frattempo rifanno il DOM, perdendo la selezione.
        row.addEventListener("mousedown", (e) => {
          e.preventDefault()
          e.stopPropagation()
          if (usernameField && entry.username) fillReact(usernameField, entry.username)
          if (passwordField) fillReact(passwordField, entry.password)
          else ricordaScelta(entry) // solo email qui: la password arriva al passo dopo
          closeDropdown()
        })
        container.appendChild(row)
        return row
      }

      // Con poche voci la ricerca è solo un campo in più da guardare prima
      // di cliccare; da tre in su invece scorrere diventa un casino, e lì
      // vale la pena.
      let search = null
      const rows = []
      // Risultati di /search: la voce può esistere nel caveau senza un url
      // che combaci con questo sito (salvata senza url, o per un sito
      // diverso) — la ricerca qui sotto guarda in TUTTO il caveau, non solo
      // fra le voci già proposte per l'host corrente.
      let ricercaAltrove = null
      let ultimaRicerca = 0
      if (entries.length > 2) {
        search = document.createElement("input")
        search.className = "hush-search"
        search.type = "text"
        search.placeholder = "Cerca…"
        // il campo di sotto non deve perdere focus/valore per colpa nostra
        search.addEventListener("mousedown", (e) => e.stopPropagation())
        search.addEventListener("input", () => {
          const q = search.value.trim().toLowerCase()
          let trovate = 0
          rows.forEach(({ row, entry }) => {
            const testo = [entry.title, entry.username, entry.projectName].filter(Boolean).join(" ").toLowerCase()
            const mostra = !q || testo.includes(q)
            row.style.display = mostra ? "" : "none"
            if (mostra) trovate++
          })
          if (ricercaAltrove) { ricercaAltrove.remove(); ricercaAltrove = null }
          if (q.length < 2 || trovate > 0) return
          const richiesta = ++ultimaRicerca
          chrome.runtime.sendMessage({ type: "search", query: q }).then((res) => {
            if (richiesta !== ultimaRicerca || search.value.trim().toLowerCase() !== q) return // digitato altro nel frattempo
            const trovateAltrove = (res && res.entries) || []
            if (trovateAltrove.length === 0) return
            ricercaAltrove = document.createElement("div")
            ricercaAltrove.className = "hush-altrove"
            const etichetta = document.createElement("div")
            etichetta.className = "hush-altrove-label"
            etichetta.textContent = "altrove nel caveau"
            ricercaAltrove.appendChild(etichetta)
            trovateAltrove.forEach((entry) => creaRiga(entry, ricercaAltrove))
            box.appendChild(ricercaAltrove)
          })
        })
        box.appendChild(search)
      }

      entries.forEach((entry) => {
        const row = creaRiga(entry, box)
        rows.push({ row, entry })
      })
      document.documentElement.appendChild(box)
      openDropdown = box
      positionAbove(box, field)
      if (search) search.focus()
    })
  }

  // Alcuni login (X, Google…) chiedono email/utente in uno schermo e la
  // password solo dopo — niente campo password da agganciare finché non si
  // arriva lì. Riconosciamo comunque il campo utente da solo.
  function looksLikeUsernameField(el) {
    const type = (el.type || "text").toLowerCase()
    if (!["text", "email", "tel"].includes(type)) return false
    const auto = (el.autocomplete || "").toLowerCase()
    if (auto === "username" || auto === "email") return true
    const hay = [el.name, el.id, el.placeholder].join(" ").toLowerCase()
    return /email|user|phone|identifier|login/.test(hay)
  }

  function attach(field, passwordField) {
    if (seen.has(field)) return
    seen.add(field)

    function reposition() {
      if (openDropdown && openField === field) positionAbove(openDropdown, field)
    }
    window.addEventListener("scroll", reposition, true)
    window.addEventListener("resize", reposition)

    // Compare da sé al focus, come i suggerimenti nativi del browser.
    field.addEventListener("focus", () => {
      const usernameField = passwordField ? usernameFieldFor(passwordField) : field
      showDropdown(field, passwordField, usernameField)
    })

    // Scrivendo si sceglie a mano: il menu sparisce.
    field.addEventListener("input", () => {
      if (openField === field) closeDropdown()
    })
  }

  function scan() {
    document.querySelectorAll('input[type="password"]').forEach((f) => attach(f, f))
    // Campi email/utente agganciati sempre, anche accanto a una password:
    // lì si riempie solo l'email, la password solo dal suo campo.
    document.querySelectorAll("input").forEach((el) => {
      if ((el.type || "text").toLowerCase() === "password") return
      if (!looksLikeUsernameField(el)) return
      attach(el, null)
    })
  }

  document.addEventListener("mousedown", (e) => {
    if (openDropdown && !openDropdown.contains(e.target) && e.target !== openField) closeDropdown()
  })

  scan()
  new MutationObserver(scan).observe(document.documentElement, { childList: true, subtree: true })
})()
