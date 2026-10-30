// Passkey buttons. <button data-passkey="login"> signs in; data-passkey="register" creates a
// passkey, for the signed-in user or, inside a form with a name field, for a new user.
// A [data-passkey-status] element on the page shows what went wrong.
(function () {
  const status = document.querySelector('[data-passkey-status]');
  const say = text => { if (status) { status.textContent = text; status.hidden = !text; } };

  const toBytes = b64url => {
    const b64 = b64url.replace(/-/g, '+').replace(/_/g, '/');
    return Uint8Array.from(atob(b64 + '='.repeat((4 - b64.length % 4) % 4)), c => c.charCodeAt(0));
  };
  const toB64url = buf => btoa(String.fromCharCode(...new Uint8Array(buf)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

  async function register(button) {
    const form = button.closest('form');
    const name = form && form.elements.name ? form.elements.name.value.trim() : undefined;
    if (form && !form.reportValidity()) return;
    const options = await postJSON(button.dataset.optionsUrl, { name });
    if (!options.ok) return say((options.data && options.data.error) || 'Something went wrong. Refresh the page and try again.');

    const publicKey = options.data;
    publicKey.challenge = toBytes(publicKey.challenge);
    publicKey.user.id = toBytes(publicKey.user.id);
    publicKey.excludeCredentials = (publicKey.excludeCredentials || []).map(c => ({ ...c, id: toBytes(c.id) }));
    const cred = await navigator.credentials.create({ publicKey });
    return finish(button.dataset.verifyUrl, {
      id: cred.id,
      rawId: toB64url(cred.rawId),
      type: cred.type,
      authenticatorAttachment: cred.authenticatorAttachment,
      clientExtensionResults: cred.getClientExtensionResults(),
      response: {
        clientDataJSON: toB64url(cred.response.clientDataJSON),
        attestationObject: toB64url(cred.response.attestationObject),
        transports: cred.response.getTransports ? cred.response.getTransports() : [],
      },
    });
  }

  async function login(button) {
    const options = await postJSON(button.dataset.optionsUrl);
    if (!options.ok) return say('Something went wrong. Refresh the page and try again.');

    const publicKey = options.data;
    publicKey.challenge = toBytes(publicKey.challenge);
    publicKey.allowCredentials = (publicKey.allowCredentials || []).map(c => ({ ...c, id: toBytes(c.id) }));
    const cred = await navigator.credentials.get({ publicKey });
    return finish(button.dataset.verifyUrl, {
      id: cred.id,
      rawId: toB64url(cred.rawId),
      type: cred.type,
      authenticatorAttachment: cred.authenticatorAttachment,
      clientExtensionResults: cred.getClientExtensionResults(),
      response: {
        clientDataJSON: toB64url(cred.response.clientDataJSON),
        authenticatorData: toB64url(cred.response.authenticatorData),
        signature: toB64url(cred.response.signature),
        userHandle: cred.response.userHandle ? toB64url(cred.response.userHandle) : null,
      },
    });
  }

  async function finish(url, credential) {
    const result = await postJSON(url, credential);
    if (result.ok) return window.location.assign(result.data.redirect);
    say((result.data && result.data.error) || 'Something went wrong. Refresh the page and try again.');
  }

  document.querySelectorAll('[data-passkey]').forEach(button => {
    if (!window.PublicKeyCredential) {
      button.disabled = true;
      say("This browser doesn't support passkeys.");
      return;
    }
    button.addEventListener('click', async e => {
      e.preventDefault();
      say('');
      button.disabled = true;
      try {
        await (button.dataset.passkey === 'login' ? login(button) : register(button));
      } catch (err) {
        // NotAllowedError: the user cancelled, or the device timed out. InvalidStateError: this
        // device already holds one of the user's passkeys.
        say(err.name === 'InvalidStateError'
          ? 'This device already has a passkey for your account.'
          : 'No passkey was used. Try again when you are ready.');
      } finally {
        button.disabled = false;
      }
    });
  });
})();
