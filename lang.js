// Shows Italian to Italian browsers, English to everyone else; the link in the menu switches.
var saved = null;
try { saved = localStorage.getItem("lang"); } catch (e) {}
var lang = saved || ((navigator.language || "en").toLowerCase().indexOf("it") === 0 ? "it" : "en");
document.documentElement.setAttribute("data-lang", lang);
document.documentElement.setAttribute("lang", lang);
function switchLanguage() {
  lang = lang === "it" ? "en" : "it";
  document.documentElement.setAttribute("data-lang", lang);
  document.documentElement.setAttribute("lang", lang);
  try { localStorage.setItem("lang", lang); } catch (e) {}
  return false;
}
