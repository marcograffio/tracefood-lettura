
// ==========================================
// Rimuovi le funzioni duplicate

supabaseClient.auth.onAuthStateChange((_, session) => {
  if (!session) {
    resetTenantSession();
    return;
  }

  user = session.user;
  if (activeTenantId && profile && profile.user_id === session.user.id) return;
  setTimeout(() => {
    if (user?.id !== session.user.id) return;
    prepareTenantSelection(session.user).catch(error => {
      document.getElementById('auth-error').textContent = 'Errore caricamento aziende: ' + (error?.message || 'imprevisto');
    });
  }, 0);
});

async function prepareTenantSelection(authUser) {
  if (tenantFlowPromise && tenantFlowUserId === authUser.id) {
    await tenantFlowPromise;
    return;
  }

  tenantFlowUserId = authUser.id;
  const currentFlow = resolveTenantSelection(authUser);
  tenantFlowPromise = currentFlow;
  try {
    await currentFlow;
  } catch (error) {
    if (user?.id === authUser.id) {
      await rejectTenantSession('Errore caricamento aziende: ' + (error?.message || 'imprevisto'));
    }
  } finally {
    if (tenantFlowPromise === currentFlow) {
      tenantFlowPromise = null;
      tenantFlowUserId = null;
    }
  }
}

async function resolveTenantSelection(authUser) {
  user = authUser;
  const { data: userProfile, error: profileError } = await supabaseClient
    .from('users')
    .select('id, user_id, nome, ruolo, is_superadmin')
    .eq('user_id', authUser.id)
    .maybeSingle();
  if (user?.id !== authUser.id) return;
  if (profileError) {
    await rejectTenantSession('Errore caricamento profilo: ' + profileError.message);
    return;
  }
  if (!userProfile) {
    await rejectTenantSession('Profilo utente non trovato.');
    return;
  }
  const isSuperadmin = Boolean(userProfile.is_superadmin || userProfile.ruolo === 'superadmin');

  const { data: memberships, error: membershipError } = await supabaseClient
    .from('user_tenants')
    .select('tenant_id, first_accessed_at, tenants!inner(id, nome_azienda, codice_univoco)')
    .eq('user_profile_id', userProfile.id);
  if (user?.id !== authUser.id) return;
  if (membershipError) {
    await rejectTenantSession('Errore caricamento aziende: ' + membershipError.message);
    return;
  }

  const availableMemberships = (memberships || [])
    .map(membership => ({
      ...membership,
      tenant: Array.isArray(membership.tenants) ? membership.tenants[0] : membership.tenants
    }))
    .filter(membership => membership.tenant);

  if (!availableMemberships.length) {
    await rejectTenantSession(isSuperadmin
      ? 'Profilo superadmin senza azienda associata. Associala dalla console Super Admin.'
      : 'Nessuna azienda disponibile per questo account. Contatta l’amministratore.');
    return;
  }

  profile = userProfile;
  tenantChoices = availableMemberships;
  if (tenantChoices.length === 1) {
    await enterTenant(tenantChoices[0]);
    return;
  }

  const select = document.getElementById('auth-tenant-select');
  select.replaceChildren();
  const placeholder = document.createElement('option');
  placeholder.value = '';
  placeholder.textContent = 'Seleziona un’azienda';
  placeholder.disabled = true;
  placeholder.selected = true;
  select.appendChild(placeholder);
  tenantChoices.forEach(membership => {
    const option = document.createElement('option');
    option.value = membership.tenant_id;
    option.textContent = membership.tenant.nome_azienda;
    select.appendChild(option);
  });
  document.getElementById('auth-credentials').classList.add('hidden');
  document.getElementById('tenant-picker-wrap').classList.remove('hidden');
  document.getElementById('btn-main').textContent = 'Continua';
  document.getElementById('btn-toggle').classList.add('hidden');
  document.querySelector('#auth-screen .link[onclick="handleForgot()"]').classList.add('hidden');
  document.getElementById('btn-cancel-tenant').classList.remove('hidden');
}

async function enterSelectedTenant() {
  const tenantId = document.getElementById('auth-tenant-select').value;
  const membership = tenantChoices.find(item => item.tenant_id === tenantId);
  if (!membership) {
    document.getElementById('auth-error').textContent = 'Seleziona un’azienda autorizzata.';
    return;
  }
  await enterTenant(membership);
}

async function enterTenant(membership) {
  const { error } = await supabaseClient.rpc('record_tenant_access', {
    p_tenant_id: membership.tenant_id
  });
  if (error) {
    document.getElementById('auth-error').textContent = 'Errore accesso azienda: ' + error.message;
    return;
  }

  activeTenant = membership.tenant;
  activeTenantId = membership.tenant_id;
  tenantChoices = [];
  document.getElementById('auth-error').textContent = '';
  document.getElementById('auth-screen').classList.add('hidden');
  document.getElementById('app-screen').classList.remove('hidden');
  document.getElementById('user-name').textContent = profile.nome;
  document.getElementById('loc-name').textContent = activeTenant.nome_azienda || 'TracciaFood';
  if (clockTimer) clearInterval(clockTimer);
  clockTimer = setInterval(() => document.getElementById('clock').textContent = new Date().toLocaleString('it-IT'), 1000);
  await loadProds();
  await loadQrCounter();
  checkQRInURL();
}

async function rejectTenantSession(message) {
  document.getElementById('auth-error').textContent = message;
  const { error } = await supabaseClient.auth.signOut();
  if (error) {
    document.getElementById('auth-error').textContent += ' Errore chiusura sessione: ' + error.message;
  }
}

async function cancelTenantChoice() {
  const { error } = await supabaseClient.auth.signOut();
  if (error) document.getElementById('auth-error').textContent = 'Errore nel cambio account: ' + error.message;
}

// ==========================================
// CARICAMENTO PRODOTTI
// ==========================================
async function loadProds() {
  const { data, error } = await supabaseClient
    .from('preparations')
    .select('*')
    .eq('tenant_id', activeTenantId)
    .order('creato_il', { ascending: false });
  if (error) {
    alert('Errore caricamento preparazioni: ' + error.message);
    return;
  }
  prods = data || [];
  render();
}

// ==========================================
// VISTE E FILTRI
// ==========================================
const VIEW_CHIPS = { active: 'chip-active', history: 'chip-storico', trash: 'chip-cestino' };

function setView(view) {
  currentView = view;
  Object.entries(VIEW_CHIPS).forEach(([name, chipId]) => {
    const chip = document.getElementById(chipId);
    if (chip) chip.classList.toggle('is-active', name === view);
  });
  const search = document.getElementById('search');
  if (search) search.value = '';
  render();
}

function render() {
  const searchEl = document.getElementById('search');
  const s = (searchEl?.value || '').toLowerCase();
  const list = document.getElementById('prod-list');
  if (!list) return;

  const filtered = prods.filter(p => {
    const deleted = Boolean(p.is_deleted || p.deleted_at);
    if (s && !(p.nome_pietanza || '').toLowerCase().includes(s)) return false;
    if (currentView === 'trash') return deleted;
    if (deleted) return false;
    if (currentView === 'history') return p.stato === 'esaurita';
    return p.stato !== 'esaurita';
  });

  if (!filtered.length) {
    const message = currentView === 'trash'
      ? 'Il cestino è vuoto.'
      : currentView === 'history'
        ? 'Nessuna preparazione archiviata.'
        : 'Nessuna preparazione.';
    list.innerHTML = `<p class="list-state">${message}</p>`;
    return;
  }

  if (!list.dataset.popupActionsBound) {
    list.addEventListener('click', event => {
      const closeButton = event.target.closest('button[data-popup-close]');
      if (closeButton) {
        const modal = closeButton.closest('.modal');
        if (modal) {
          modal.classList.remove('show');
          modal.setAttribute('aria-hidden', 'true');
        }
        return;
      }

      const openButton = event.target.closest('button[data-popup-modal]');
      if (!openButton) return;
      const modal = document.getElementById(openButton.dataset.popupModal);
      if (!modal || !list.contains(modal)) return;
      modal.classList.add('show');
      modal.setAttribute('aria-hidden', 'false');
    });
    list.dataset.popupActionsBound = 'true';
  }

  list.innerHTML = filtered.map(p => {
    const qr = p.qr_code_univoco || null;
    const att = p.stato === 'attiva';
    const statusLabel = att ? '' : '<span class="badge">ESAURITO</span>';
    
    return `<div class="card" role="button" tabindex="0" onclick="openDetail('${p.id}')" onkeydown="if(event.key==='Enter')openDetail('${p.id}')">
      <h3>${escapeHtml(p.nome_pietanza)} ${statusLabel}</h3>
      <p><b>Data:</b> ${p.data_preparazione || '—'}</p>
      ${qr ? `<p><b>QR:</b> ${qr}</p>` : ''}
    </div>`;
  }).join('');
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, character => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  })[character]);
}

// ==========================================
// DETTAGLIO E AZIONI
// ==========================================

function openDetail(id) {
  const p = prods.find(x => x.id === id);
  if (!p) return;

  const modal = document.getElementById('m-detail');
  if (!modal) return;

  // Popolamento modale (usando gli ID corretti da index.html)
  modal.querySelector('#d-title').textContent = p.nome_pietanza || 'Preparazione';
  modal.querySelector('#d-data').textContent = p.data_preparazione || '—';
  modal.querySelector('#d-qr').textContent = p.qr_code_univoco || '—';
  modal.querySelector('#d-stato').textContent = p.stato === 'attiva' ? 'Attiva' : 'Esaurita';
  
  // Ingredienti
  const ingList = modal.querySelector('#d-ingredients');
  ingList.innerHTML = (p.ingredienti || []).map(i => `<li>${escapeHtml(i.nome)} (${i.quantita} ${i.unita})</li>`).join('');

  // Note
  const noteWrap = modal.querySelector('#d-note-wrap');
  const noteEl = modal.querySelector('#d-note');
  if (p.note) {
    noteWrap.classList.remove('hidden');
    noteEl.textContent = p.note;
  } else {
    noteWrap.classList.add('hidden');
  }

  // Gestione pulsante azioni in alto a destra
  const menuBtn = modal.querySelector('#detail-menu-button');
  menuBtn.onclick = () => openActions(p.id);

  modal.classList.add('show');
  modal.setAttribute('aria-hidden', 'false');
}

function openActions(id) {
  const p = prods.find(x => x.id === id);
  if (!p) return;
  
  const modal = document.getElementById('m-actions');
  modal.dataset.currentId = id;
  
  // Le azioni sono già presenti in index.html, le colleghiamo qui
  modal.querySelector('button[onclick="segnaComeFinita()"]').onclick = () => { segnaComeFinita(id); modal.classList.remove('show'); };
  modal.querySelector('button[onclick="stampaScheda()"]').onclick = () => { stampaScheda(id); modal.classList.remove('show'); };
  modal.querySelector('button[onclick="correggiDaScheda()"]').onclick = () => { correggiDaScheda(id); modal.classList.remove('show'); };
  modal.querySelector('button[onclick="cancellaDaScheda()"]').onclick = () => { cancellaDaScheda(id); modal.classList.remove('show'); };

  modal.classList.add('show');
  modal.setAttribute('aria-hidden', 'false');
}

async function cancellaDaScheda() {
  const modal = document.getElementById('m-actions');
  const id = modal.dataset.currentId;
  modal.classList.remove('show');
  closeModal('m-detail');
  
  await moveIntoTrash(id);
  showToast('Spostato nel cestino', 'Annulla', () => undoEliminazione(id));
  loadProds();
}

async function correggiDaScheda() {
  const modal = document.getElementById('m-actions');
  const id = modal.dataset.currentId;
  modal.classList.remove('show');
  closeModal('m-detail');
  openForm(id);
}
async function openForm(id = null, qrId = null, qrCode = null, allowReassign = false) {
  document.getElementById('form').reset();
  document.getElementById('edit-id').value = id || '';
  pendingQrId = qrId;
  pendingQrCode = qrCode;
  document.getElementById('form-submit-label').textContent = qrId ? 'Conferma' : 'Salva';
  document.getElementById('form-submit-button').setAttribute('aria-label', qrId ? 'Conferma' : 'Salva');
  document.getElementById('photo-box').classList.remove('is-visible');
  document.getElementById('photo-prev').removeAttribute('src');
  document.getElementById('ingredients-container').innerHTML = '';
  photoB64 = null;
  ingredientRows = [];
  document.getElementById('note-text-main').value = '';
  const preparationSelectWrap = document.getElementById('qr-preparation-select-wrap');
  const preparationSelect = document.getElementById('qr-preparation-select');
  preparationSelectWrap.classList.toggle('hidden', !allowReassign);
  preparationSelect.replaceChildren();
  if (allowReassign) {
    const newPreparationOption = document.createElement('option');
    newPreparationOption.value = '';
    newPreparationOption.textContent = 'Nuova preparazione';
    preparationSelect.appendChild(newPreparationOption);
    prods
      .filter(product => !product.is_deleted && product.tenant_id === activeTenantId)
      .forEach(product => {
        const option = document.createElement('option');
        option.value = product.id;
        option.textContent = `${product.nome_pietanza || 'Senza nome'}${product.data_preparazione ? ` — ${product.data_preparazione}` : ''}`;
        preparationSelect.appendChild(option);
      });
    preparationSelect.value = id || '';
  }

  document.getElementById('f-title').textContent = allowReassign
    ? 'Modifica / Abbina'
    : id ? 'Modifica' : 'Nuova Preparazione';
  document.getElementById('btn-reuse-container').classList.toggle('hidden', !(allowReassign && id));
  
  if (id) {
    const p = prods.find(x => x.id === id);
    if (p) {
      document.getElementById('f-nome').value = p.nome_pietanza || '';
      document.getElementById('f-data').value = dateForInput(p.data_preparazione);
      document.getElementById('note-text-main').value = p.note || '';
      if (p.foto_url) {
        photoB64 = p.foto_url;
        document.getElementById('photo-prev').src = p.foto_url;
        document.getElementById('photo-box').classList.add('is-visible');
      }
      try {
        await loadPreparationIngredients(id);
      } catch (error) {
        alert('Errore caricamento ingredienti: ' + error.message);
        return;
      }
    }
  }
  document.getElementById('m-form').classList.add('show');
}

async function handleQrPreparationChange() {
  const preparationId = document.getElementById('qr-preparation-select').value || null;
  await openForm(preparationId, pendingQrId, pendingQrCode, true);
}

function dateForInput(value) {
  const dateParts = (value || '').match(/^(\d{2})\/(\d{2})\/(\d{2}|\d{4})$/);
  if (!dateParts) return value || '';

  const year = dateParts[3].length === 2 ? `20${dateParts[3]}` : dateParts[3];
  return `${year}-${dateParts[2]}-${dateParts[1]}`;
}

function addIngredientRow(nome = '', lotto = '') {
  const container = document.getElementById('ingredients-container');
  const row = document.createElement('div');
  row.className = 'ingredient-row';
  const fields = document.createElement('div');
  fields.className = 'ingredient-fields';
  const nameField = document.createElement('div');
  nameField.className = 'ingredient-field';
  const nameLabel = document.createElement('label');
  nameLabel.textContent = 'Ingrediente';
  const nameInput = document.createElement('input');
  nameInput.type = 'text';
  nameInput.className = 'ing-nome';
  nameInput.value = nome;
  nameInput.placeholder = 'Es. pomodori';
  nameField.append(nameLabel, nameInput);
  const lotField = document.createElement('div');
  lotField.className = 'ingredient-field';
  const lotLabel = document.createElement('label');
  lotLabel.textContent = 'Lotto';
  const lotInput = document.createElement('input');
  lotInput.type = 'text';
  lotInput.className = 'ing-lotto';
  lotInput.value = lotto;
  lotInput.placeholder = 'Es. LOT-001';
  lotField.append(lotLabel, lotInput);
  fields.append(nameField, lotField);
  row.appendChild(fields);
  container.appendChild(row);
  ingredientRows.push(row);
}

function removeIngredientRow() {
  if (ingredientRows.length > 0) {
    const last = ingredientRows.pop();
    last.remove();
  }
}

// ==========================================
// GESTIONE FOTO
// ==========================================
function openCamera() {
  const choice = confirm('Premi OK per Scattare Foto, ANNULLA per Scansionare QR');
  if (choice) {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = 'image/*';
  input.capture = 'environment';
  input.onchange = (e) => previewPhoto(e);
  input.click();
  } else {
    openScanner();
  }
}

function previewPhoto(e) {
  const f = e.target.files[0]; if (!f) return;
  const r = new FileReader();
  r.onload = () => {
    const img = new Image();
    img.onload = () => {
      const c = document.createElement('canvas');
      c.width = 800;
      c.height = img.height * 800 / img.width;
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      photoB64 = c.toDataURL('image/jpeg', 0.7);
      document.getElementById('photo-prev').src = photoB64;
      document.getElementById('photo-box').classList.add('is-visible');
    };
    img.src = r.result;
  };
  r.readAsDataURL(f);
}

function removePhoto() {
  photoB64 = null;
  document.getElementById('photo-box').classList.remove('is-visible');
}
// ==========================================
// GESTIONE NOTE
// ==========================================
async function loadPreparationIngredients(preparationId) {
  const { data, error } = await supabaseClient
    .from('preparation_ingredients')
    .select('ingrediente, ingredient_lot_id')
    .eq('tenant_id', activeTenantId)
    .eq('preparation_id', preparationId)
    .order('creato_il');
  if (error) throw new Error(error.message);

  const lotIds = [...new Set((data || []).map(row => row.ingredient_lot_id).filter(Boolean))];
  const lotsById = new Map();
  if (lotIds.length) {
    const { data: lots, error: lotsError } = await supabaseClient
      .from('ingredient_lots')
      .select('id, numero_lotto')
      .eq('tenant_id', activeTenantId)
      .in('id', lotIds);
    if (lotsError) throw new Error(lotsError.message);
    (lots || []).forEach(lot => lotsById.set(lot.id, lot.numero_lotto || ''));
  }

  (data || []).forEach(row => {
    addIngredientRow(row.ingrediente, lotsById.get(row.ingredient_lot_id) || '');
  });
}

async function getOrCreateIngredientLot(ingrediente, numeroLotto) {
  if (!numeroLotto) return null;

  const { data: existing, error: lookupError } = await supabaseClient
    .from('ingredient_lots')
    .select('id')
    .eq('tenant_id', activeTenantId)
    .eq('ingrediente', ingrediente)
    .eq('numero_lotto', numeroLotto)
    .limit(1)
    .maybeSingle();
  if (lookupError) throw new Error(lookupError.message);
  if (existing) return existing.id;

  const { data: inserted, error: insertError } = await supabaseClient
    .from('ingredient_lots')
    .insert({
      tenant_id: activeTenantId,
      ingrediente,
      numero_lotto: numeroLotto
    })
    .select('id')
    .single();
  if (insertError) throw new Error(insertError.message);
  return inserted.id;
}

async function savePreparationIngredients(preparationId) {
  const { data: previousRows, error: readError } = await supabaseClient
    .from('preparation_ingredients')
    .select('tenant_id, preparation_id, ingredient_lot_id, ingrediente, quantita, unita, note, creato_da')
    .eq('tenant_id', activeTenantId)
    .eq('preparation_id', preparationId);
  if (readError) throw new Error(readError.message);

  const rows = [];
  for (const row of document.querySelectorAll('.ingredient-row')) {
    const ingrediente = row.querySelector('.ing-nome').value.trim();
    const numeroLotto = row.querySelector('.ing-lotto').value.trim();
    if (!ingrediente) continue;

    const ingredientLotId = await getOrCreateIngredientLot(ingrediente, numeroLotto);
    rows.push({
      tenant_id: activeTenantId,
      preparation_id: preparationId,
      ingredient_lot_id: ingredientLotId,
      ingrediente
    });
  }

  const { error: deleteError } = await supabaseClient
    .from('preparation_ingredients')
    .delete()
    .eq('tenant_id', activeTenantId)
    .eq('preparation_id', preparationId);
  if (deleteError) throw new Error(deleteError.message);

  if (!rows.length) return;
  const { error: insertError } = await supabaseClient
    .from('preparation_ingredients')
    .insert(rows);
  if (!insertError) return;

  if (previousRows?.length) {
    const { error: restoreError } = await supabaseClient
      .from('preparation_ingredients')
      .insert(previousRows);
    if (restoreError) {
      throw new Error(`${insertError.message}; ripristino ingredienti precedenti fallito: ${restoreError.message}`);
    }
  }
  throw new Error(insertError.message);
}
// ==========================================
// SALVATAGGIO
// ==========================================
async function saveProduct(e) {
  e.preventDefault();
  const id = document.getElementById('edit-id').value;
  const nome = document.getElementById('f-nome').value.trim();
  const dataStr = document.getElementById('f-data').value.trim();
  const dateParts = dataStr.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  const formattedDate = dateParts ? `${dateParts[3]}/${dateParts[2]}/${dateParts[1]}` : '';
  const existingProduct = id ? prods.find(product => product.id === id) : null;
  
  if (!nome) return alert('Nome obbligatorio');

  const obj = {
    nome_pietanza: nome,
    data_preparazione: formattedDate || null,
    note: document.getElementById('note-text-main').value.trim() || null,
    foto_url: photoB64 || null,
    abbattuto: existingProduct?.abbattuto ?? false,
    qr_code_univoco: pendingQrCode || existingProduct?.qr_code_univoco || null,
    tenant_id: activeTenantId
  };
  
  let prepId = id;

  if (pendingQrId) {
    const { data: confirmedId, error } = await supabaseClient.rpc('confirm_qr_preparation', {
      p_tenant_id: activeTenantId,
      p_qr_id: pendingQrId,
      p_preparation_id: id || null,
      p_nome: nome,
      p_data_preparazione: formattedDate || null,
      p_note: obj.note,
      p_foto_url: obj.foto_url
    });
    if (error) return alert('Errore conferma QR: ' + error.message);
    prepId = confirmedId;
    document.getElementById('edit-id').value = prepId;
  } else if (id) {
    const { error } = await supabaseClient
      .from('preparations')
      .update(obj)
      .eq('tenant_id', activeTenantId)
      .eq('id', id);
    if (error) return alert('Errore: ' + error.message);
  } else {
    obj.creato_da = profile.id;
    const { data: inserted, error } = await supabaseClient
      .from('preparations')
      .insert([obj])
      .select('id')
      .single();
    if (error) return alert('Errore: ' + error.message);
    prepId = inserted.id;
    document.getElementById('edit-id').value = prepId;
  }
  
  if (!prepId) return alert('Errore: preparazione non salvata.');

  try {
    await savePreparationIngredients(prepId);
  } catch (error) {
    return alert('Preparazione salvata, ma errore nel salvataggio degli ingredienti: ' + error.message);
  }

  pendingQrId = null;
  pendingQrCode = null;
  closeModal('m-form');
  await loadProds();
  await loadQrCounter();
}

// ==========================================
// AZIONI PRODOTTO
// ==========================================
async function riattiva(id) {
  if (!confirm('Riattivare?')) return;
  const { error } = await supabaseClient
    .from('preparations')
    .update({ stato: 'attiva' })
    .eq('tenant_id', activeTenantId)
    .eq('id', id);
  if (error) return alert('Errore: ' + error.message);
  await loadProds();
}

async function ripristinaProdotto(id) {
  const { error } = await supabaseClient
    .from('preparations')
    .update({ is_deleted: false, deleted_at: null })
    .eq('tenant_id', activeTenantId)
    .eq('id', id);
  if (error) return alert('Errore: ' + error.message);
  await loadProds();
}

async function eliminaProdotto(id) {
  const product = prods.find(item => item.id === id);
  if (!product) return alert('Prodotto non trovato.');

  if (product.is_deleted || product.deleted_at) {
    if (!confirm('Sei sicuro di voler eliminare definitivamente?')) return;

    const { error } = await supabaseClient
      .from('preparations')
      .delete()
      .eq('tenant_id', activeTenantId)
      .eq('id', id);
    if (error) return alert('Errore: ' + error.message);

    await loadProds();
    return;
  }

  product.is_deleted = true;
  product.deleted_at = new Date().toISOString();
  render();
  const { error } = await supabaseClient
    .from('preparations')
    .update({ is_deleted: true, deleted_at: product.deleted_at })
    .eq('tenant_id', activeTenantId)
    .eq('id', id);
  if (error) {
    product.is_deleted = false;
    product.deleted_at = null;
    render();
    return alert('Errore: ' + error.message);
  }
}

function closeModal(id) { document.getElementById(id).classList.remove('show'); }

function annullaForm() {
  pendingQrId = null;
  pendingQrCode = null;
  closeModal('m-form');
}

// ==========================================
// QR CODE E SCANNER
// ==========================================
async function showQR(code) {
  if (!code) return alert('Nessun QR.');
  const box = document.getElementById('qr-box'); box.innerHTML = '';
  const url = new URL(window.location.href);
  url.searchParams.set('qr', code);
  new QRCode(box, { text: url.toString(), width: 250, height: 250 });
  document.getElementById('m-qr').classList.add('show');
}

async function showPrintModal() {
  const id = document.getElementById('edit-id').value;
  if (!id) return alert('Salva prima il prodotto.');
  const p = prods.find(x => x.id === id);
  if (!p?.qr_code_univoco) return alert('QR non disponibile.');

  const box = document.getElementById('qr-box'); box.innerHTML = '';
  const url = new URL(window.location.href);
  url.searchParams.set('qr', p.qr_code_univoco);
  new QRCode(box, { text: url.toString(), width: 250, height: 250 });
  document.getElementById('m-qr').classList.add('show');
}

async function openScanner() {
  document.getElementById('m-scan').classList.add('show');
  try {
    scanner = new Html5Qrcode("reader");
    await scanner.start({ facingMode: "environment" }, { fps: 10, qrbox: 250 }, async (text) => {
      await closeScanner();
      await handleScan(text);
    });
  } catch (error) {
    const failedScanner = scanner;
    scanner = null;
    if (failedScanner) {
      try {
        failedScanner.clear();
      } catch (cleanupError) {
        alert('Errore pulizia fotocamera: ' + cleanupError.message);
      }
    }
    closeModal('m-scan');
    alert('Errore avvio fotocamera: ' + error.message);
  }
}

async function handleScan(text) {
  if (scanHandling) return;
  scanHandling = true;
  try {
    await processScan(text);
  } finally {
    scanHandling = false;
  }
}

const QR_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

function qrChecksum(body) {
  let value = 0;
  for (const char of body) {
    const index = QR_ALPHABET.indexOf(char);
    if (index < 0) return null;
    value = (value * 32 + index) % 97;
  }
  return String(value).padStart(2, '0');
}

function inspectQrCode(code, companyCode) {
  const match = /^(.*)-([0-9A-Z]{8})-([0-9]{2})$/.exec(code);
  if (!match) return 'legacy';
  const [, prefix, body, check] = match;
  if (qrChecksum(body) !== check) return 'invalid';
  if (prefix.toUpperCase() !== String(companyCode || '').toUpperCase()) return 'other-company';
  return 'new';
}

async function loadQrCounter() {
  const el = document.getElementById('qr-counter');
  if (!el || !activeTenantId) return;
  const { count, error } = await supabaseClient
    .from('qr_pool')
    .select('id', { count: 'exact', head: true })
    .eq('tenant_id', activeTenantId)
    .eq('stato', 'disponibile');
  el.textContent = error ? '' : `QR disponibili: ${count ?? 0}`;
}

function riusaContenitore() {
  openForm(null, pendingQrId, pendingQrCode, true);
}

async function processScan(text) {
  const rawText = String(text || '').trim();
  if (!rawText) return;

  let code = rawText;
  try {
    code = new URL(rawText, window.location.href).searchParams.get('qr') || rawText;
  } catch {
    code = rawText;
  }

  if (!code) return;
  const companyCode = activeTenant?.codice_univoco || '';
  if (!companyCode) return alert('Codice azienda non disponibile.');

  const inspection = inspectQrCode(code, companyCode);
  if (inspection === 'invalid') return alert('QR non valido (codice corrotto).');
  if (inspection === 'other-company') return alert('QR di altra azienda');

  const { data: qr, error } = await supabaseClient.from('qr_pool')
    .select('id, codice_univoco, stato, preparation_id')
    .eq('tenant_id', activeTenantId)
    .eq('codice_univoco', code)
    .maybeSingle();

  if (error) return alert('Errore nella lettura del QR: ' + error.message);
  if (!qr) return alert('QR non valido o non riconosciuto.');
  if (qr.stato === 'scaduto') return alert('QR scaduto.');

  if (qr.stato === 'disponibile' && !qr.preparation_id) {
    openForm(null, qr.id, qr.codice_univoco);
    return;
  }
  if (qr.stato !== 'assegnato' || !qr.preparation_id) {
    return alert('Stato del QR non coerente. Contatta l’amministratore.');
  }

  let preparation = prods.find(item => item.id === qr.preparation_id);
  if (!preparation) {
    await loadProds();
    preparation = prods.find(item => item.id === qr.preparation_id);
  }
  if (!preparation) return alert('Preparazione associata non trovata.');
  if (preparation.is_deleted || preparation.deleted_at) {
    openForm(null, qr.id, qr.codice_univoco);
    return;
  }
  openForm(preparation.id, qr.id, qr.codice_univoco, true);
}

async function closeScanner() {
  if (!scanner) {
    closeModal('m-scan');
    return;
  }
  const activeScanner = scanner;
  try {
    await activeScanner.stop();
  } catch (error) {
    alert('Errore chiusura fotocamera: ' + error.message);
    return;
  }
  try {
    activeScanner.clear();
  } catch (error) {
    alert('Errore pulizia fotocamera: ' + error.message);
  }
  scanner = null;
  closeModal('m-scan');
}

function checkQRInURL() {
  const url = new URL(window.location.href);
  const qrCode = url.searchParams.get('qr');
  if (qrCode) {
    url.searchParams.delete('qr');
    window.history.replaceState({}, document.title, url.toString());
    handleScan(qrCode);
  }
}

// ==========================================
// INIZIALIZZAZIONE
// ==========================================
document.getElementById('search').addEventListener('input', render);

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => navigator.serviceWorker.register('sw.js').catch(() => {}));
}

