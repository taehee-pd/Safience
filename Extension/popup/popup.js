// The popup: signing in, pairing this profile with a space, and the
// space's tabs on other devices. All the work is the service worker's.

const $ = (id) => document.getElementById(id);

// The colours of Safience's spaces, by name (SpaceColor).
const COLORS = {
  blue: '#0a84ff', purple: '#bf5af2', pink: '#ff375f', red: '#ff453a', orange: '#ff9f0a', yellow: '#ffd60a',
  green: '#30d158', teal: '#40c8e0', indigo: '#5e5ce6', gray: '#8e8e93',
};

async function ask(type, extra = {}) {
  const answer = await chrome.runtime.sendMessage({ type, ...extra });
  if (!answer?.ok) throw new Error(answer?.error || 'Something went wrong.');
  return answer.value;
}

function showError(message) {
  $('error').textContent = message || '';
  $('error').hidden = !message;
}

function ago(time) {
  if (!time) return 'Not synced yet';
  const minutes = Math.round((Date.now() - time) / 60000);
  if (minutes < 1) return 'Synced just now';
  if (minutes < 60) return `Synced ${minutes} min ago`;
  const hours = Math.round(minutes / 60);
  return hours < 24 ? `Synced ${hours} h ago` : `Synced ${new Date(time).toLocaleDateString()}`;
}

function host(address) {
  try { return new URL(address).hostname.replace(/^www\./, ''); } catch (_) { return address; }
}

function render(status) {
  $('setup').hidden = status.configured;
  $('redirect').textContent = status.redirect;
  $('signin').hidden = !status.configured || status.signedIn;
  $('pair').hidden = !status.signedIn || !!status.paired;
  $('paired').hidden = !status.signedIn || !status.paired;
  $('footer').hidden = !status.signedIn;
  $('unpair-button').hidden = !status.paired;
  showError(status.error);

  if (status.signedIn && !status.paired) {
    // Made again on every refresh: the space chosen stays chosen.
    const chosen = document.querySelector('input[name="space"]:checked')?.value;
    const list = $('spaces');
    list.replaceChildren(...status.spaces.map((space) => {
      const label = document.createElement('label');
      label.className = 'choice';
      const radio = Object.assign(document.createElement('input'), {
        type: 'radio', name: 'space', value: space.id, checked: space.id === chosen,
      });
      const dot = document.createElement('span');
      dot.className = 'dot';
      dot.style.background = COLORS[space.color] || COLORS.gray;
      const name = document.createElement('span');
      name.textContent = space.name;
      label.append(radio, dot, name);
      return label;
    }));
    if (!$('new-name').value) $('new-name').value = status.browser;
    updatePairButton();
  }

  if (status.paired) {
    $('space-name').textContent = status.spaceName || 'Space';
    $('space-name').style.background = COLORS[status.spaceColor] || '';
    // Dark words on yellow, white on the rest, as Safience's space button has them.
    $('space-name').style.color = status.spaceColor === 'yellow' ? '#1a1a1a' : status.spaceColor ? '#ffffff' : '';
    $('last-sync').textContent = ago(status.lastSync);
    $('follower').hidden = status.writer;
    if (document.activeElement !== $('device-name')) $('device-name').value = status.deviceName;
    $('elsewhere').replaceChildren(...status.elsewhere.map((device) => {
      const block = document.createElement('section');
      block.className = 'device-tabs';
      const heading = document.createElement('h3');
      heading.textContent = `${device.browser} · ${device.deviceName}`;
      const list = document.createElement('ul');
      for (const tab of device.tabs) {
        const item = document.createElement('li');
        const button = document.createElement('button');
        const title = Object.assign(document.createElement('span'), { className: 'title', textContent: tab.t || host(tab.u) });
        const where = Object.assign(document.createElement('span'), { className: 'host', textContent: host(tab.u) });
        button.append(title, where);
        button.addEventListener('click', () => ask('open', { url: tab.u }));
        item.append(button);
        list.append(item);
      }
      block.append(heading, list);
      return block;
    }));
  }
}

function updatePairButton() {
  const chosen = document.querySelector('input[name="space"]:checked');
  $('pair-button').disabled = !chosen || (chosen.value === '' && !$('new-name').value.trim());
}

async function run(button, type, extra) {
  button.disabled = true;
  showError('');
  try {
    render(await ask(type, extra));
  } catch (error) {
    showError(error.message);
  } finally {
    button.disabled = false;
  }
}

$('signin-button').addEventListener('click', (e) => run(e.currentTarget, 'signIn'));
$('signout-button').addEventListener('click', (e) => run(e.currentTarget, 'signOut'));
$('unpair-button').addEventListener('click', (e) => run(e.currentTarget, 'unpair'));
$('sync-button').addEventListener('click', (e) => run(e.currentTarget, 'syncNow'));
$('writer-button').addEventListener('click', (e) => run(e.currentTarget, 'becomeWriter'));
$('pair').addEventListener('change', updatePairButton);
$('new-name').addEventListener('input', () => {
  const fresh = document.querySelector('input[name="space"][value=""]');
  if (fresh) fresh.checked = true;
  updatePairButton();
});
$('pair-button').addEventListener('click', (e) => {
  const chosen = document.querySelector('input[name="space"]:checked');
  run(e.currentTarget, 'pair', chosen.value ? { space: chosen.value } : { name: $('new-name').value.trim() });
});
$('device-name').addEventListener('change', (e) => ask('rename', { deviceName: e.currentTarget.value }).then(render, (error) => showError(error.message)));

ask('status').then(render, (error) => showError(error.message));
// Then what has changed since.
ask('syncNow').then(render, () => {});
