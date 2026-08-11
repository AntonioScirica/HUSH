// Fa da ponte fra le pagine (content.js) e la parte nativa Swift
// (SafariWebExtensionHandler), che a sua volta parla in loopback con Hush.app.
// Qui non c'è nessuna password: solo l'inoltro dei messaggi.

function askNative(message) {
  return browser.runtime.sendNativeMessage("application.id", message)
}

browser.runtime.onMessage.addListener((message) => {
  return askNative(message)
})
