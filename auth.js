// Auth Module - Logica di autenticazione, registrazione e gestione sessioni.
// Dipendenze: supabaseClient (globale)

window.handleAuth = async function handleAuth() {
  const err = document.getElementById('auth-error');
  err.textContent = '';
  try {
    if (isLogin) {
      if (user && !document.getElementById('tenant-picker-wrap').classList.contains('hidden')) {
        await enterSelectedTenant();
        return;
      }
      const email = document.getElementById('auth-email').value.trim();
      const pass = document.getElementById('auth-password').value;
      if (!email || !pass) return err.textContent = 'Inserisci email e password.';
      const { data, error } = await supabaseClient.auth.signInWithPassword({ email, password: pass });
      if (error) return err.textContent = error.message;
      document.getElementById('auth-password').value = '';
      await prepareTenantSelection(data.user);
    } else {
      const email = document.getElementById('auth-email').value.trim();
      const pass = document.getElementById('auth-password').value;
      if (!email || !pass) return err.textContent = 'Inserisci email e password.';
      const nome = document.getElementById('auth-nome').value.trim();
      if (!nome) return err.textContent = 'Inserisci Nome Cognome.';
      const { error } = await supabaseClient.auth.signUp({ email, password: pass, options: { data: { nome: nome, ruolo: 'cliente' } } });
      if (error) return err.textContent = error.message;
      alert('Registrato! Controlla la mail.'); toggleAuth();
    }
  } catch (error) {
    err.textContent = 'Errore di autenticazione: ' + (error?.message || 'imprevisto');
  }
}

window.toggleAuth = function toggleAuth() {
  isLogin = !isLogin;
  document.getElementById('reg-fields').classList.toggle('hidden', isLogin);
  document.getElementById('btn-main').textContent = isLogin ? 'Accedi' : 'Registrati';
  document.getElementById('btn-toggle').textContent = isLogin ? 'Registrati' : 'Accedi';
  document.getElementById('auth-error').textContent = '';
}

window.handleForgot = async function handleForgot() {
  const email = document.getElementById('auth-email').value.trim();
  if (!email) return alert('Inserisci la tua email.');
  try {
    const { error } = await supabaseClient.auth.resetPasswordForEmail(email);
    if (error) throw error;
    alert('Email inviata!');
  } catch (error) {
    alert('Errore invio email: ' + (error?.message || 'imprevisto'));
  }
}

window.logout = async function logout() {
  try {
    await supabaseClient.auth.signOut();
  } catch (error) {
    alert('Errore nel logout: ' + (error?.message || 'imprevisto'));
  }
}

window.resetTenantSession = function resetTenantSession() {
  user = null;
  profile = null;
  activeTenant = null;
  activeTenantId = null;
  tenantChoices = [];
  pendingQrId = null;
  pendingQrCode = null;
  document.getElementById('app-screen').classList.add('hidden');
  document.getElementById('auth-screen').classList.remove('hidden');
  document.getElementById('auth-credentials').classList.remove('hidden');
  document.getElementById('tenant-picker-wrap').classList.add('hidden');
  document.getElementById('btn-main').textContent = isLogin ? 'Accedi' : 'Registrati';
  document.getElementById('btn-toggle').classList.remove('hidden');
  document.querySelector('#auth-screen .link[onclick="handleForgot()"]')?.classList.remove('hidden');
  document.getElementById('btn-cancel-tenant').classList.add('hidden');
}
