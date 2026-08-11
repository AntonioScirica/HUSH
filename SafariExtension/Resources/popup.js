const pallino = document.getElementById("pallino")
const titolo = document.getElementById("titolo")
const testo = document.getElementById("testo")

browser.runtime.sendMessage({ type: "status" }).then((res) => {
  if (res && res.unlocked) {
    pallino.classList.add("ok")
    titolo.textContent = "Hush è sbloccato"
    testo.textContent = "Apri un campo password in una pagina e tocca il tasto 🔒 per compilarlo."
  } else if (res && res.hasVault) {
    titolo.textContent = "Hush è chiuso"
    testo.textContent = "Apri Hush sul Mac e sblocca il caveau: da qui il tasto 🔒 tornerà a funzionare."
  } else if (res && res.error === "unreachable") {
    titolo.textContent = "Hush non è aperto"
    testo.textContent = "Apri l'app Hush sul Mac almeno una volta per collegare l'estensione."
  } else {
    titolo.textContent = "Nessun vault"
    testo.textContent = "Apri Hush e crea o importa il tuo primo progetto."
  }
}).catch(() => {
  titolo.textContent = "Hush non è aperto"
  testo.textContent = "Apri l'app Hush sul Mac almeno una volta per collegare l'estensione."
})
