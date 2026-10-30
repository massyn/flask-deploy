// POST JSON from a page script with the page's CSRF token, which Flask-WTF reads from the
// X-CSRFToken header. Resolves to { ok, status, data } where data is the parsed JSON reply, or null.
window.postJSON = async (url, body) => {
  const token = document.querySelector('meta[name="csrf-token"]').content;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-CSRFToken': token },
    body: JSON.stringify(body || {}),
  });
  let data = null;
  try { data = await res.json(); } catch (err) { /* not JSON: an expired token or server error page */ }
  return { ok: res.ok, status: res.status, data };
};
