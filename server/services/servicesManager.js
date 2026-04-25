const { execSync, spawn } = require('child_process');

const MANAGED_CONTAINERS = [
  { name: 'devplatform-portal', label: 'Portal', critical: true, allowRestart: true },
  { name: 'nginx-proxy', label: 'Nginx', critical: true, allowRestart: true },
  { name: 'devplatform-postgres', label: 'PostgreSQL', critical: true, allowRestart: true },
  { name: 'devplatform-mysql', label: 'MySQL', critical: true, allowRestart: true },
  { name: 'devplatform-pgadmin', label: 'pgAdmin', critical: false, allowRestart: true },
  { name: 'devplatform-phpmyadmin', label: 'phpMyAdmin', critical: false, allowRestart: true },
  { name: 'devplatform-filebrowser', label: 'File Browser', critical: false, allowRestart: true },
];

function listServices() {
  let psOutput = '';
  try {
    psOutput = execSync(
      'docker ps -a --format "{{.Names}}|{{.State}}|{{.Status}}|{{.Image}}"',
      { encoding: 'utf8', timeout: 5000 }
    );
  } catch (e) {
    return { success: false, message: 'Tidak bisa baca docker ps: ' + e.message, services: [] };
  }

  const containerMap = {};
  psOutput.split('\n').filter(Boolean).forEach(line => {
    const [name, state, status, image] = line.split('|');
    containerMap[name] = { state, status, image };
  });

  const services = MANAGED_CONTAINERS.map(svc => {
    const c = containerMap[svc.name];
    return {
      name: svc.name,
      label: svc.label,
      critical: svc.critical,
      allowRestart: svc.allowRestart,
      state: c ? c.state : 'missing',
      status: c ? c.status : 'Container tidak ada (jalankan docker compose up -d)',
      image: c ? c.image : '',
      running: c?.state === 'running',
    };
  });

  return { success: true, services };
}

function restartService(name) {
  const allowed = MANAGED_CONTAINERS.find(s => s.name === name && s.allowRestart);
  if (!allowed) return { success: false, message: 'Container tidak boleh di-restart dari sini.' };

  if (name === 'devplatform-portal') {
    setTimeout(() => {
      try { spawn('docker', ['restart', name], { detached: true, stdio: 'ignore' }).unref(); } catch {}
    }, 500);
    return {
      success: true,
      message: 'Portal akan restart dalam 1-2 detik. Halaman ini akan hang sebentar — refresh setelah 10 detik.',
      portalSelfRestart: true,
    };
  }

  try {
    execSync(`docker restart ${name}`, { encoding: 'utf8', timeout: 30000 });
    return { success: true, message: `${name} berhasil di-restart.` };
  } catch (e) {
    return { success: false, message: `Restart ${name} gagal: ${e.message}` };
  }
}

function getDockerStats() {
  try {
    const out = execSync(
      'docker stats --no-stream --format "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}"',
      { encoding: 'utf8', timeout: 8000 }
    );
    return out.split('\n').filter(Boolean).map(line => {
      const [name, cpu, mem, memPct] = line.split('|');
      return { name, cpu, mem, memPct };
    });
  } catch (e) {
    return [];
  }
}

module.exports = { listServices, restartService, getDockerStats };
