const express = require('express');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const router = express.Router();

const USERS_FILE = path.join(__dirname, '../data/users.json');

function requireAuth(req, res, next) {
  if (!req.session || !req.session.user) return res.status(401).json({ error: 'Unauthorized' });
  next();
}

function requireAdmin(req, res, next) {
  if (!req.session || !req.session.user) return res.status(401).json({ error: 'Unauthorized' });
  if (req.session.user.role !== 'admin') return res.status(403).json({ error: 'Forbidden' });
  next();
}

function getDockerStats() {
  try {
    const output = execSync(
      'docker stats --no-stream --format "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.NetIO}}"',
      { timeout: 5000, encoding: 'utf8' }
    );
    return output.trim().split('\n').map(line => {
      const [name, cpu, mem, memPerc, net] = line.split('|');
      return { name, cpu, mem, memPerc, net };
    }).filter(s => s.name && s.name.startsWith('codeserver-'));
  } catch {
    return getMockStats();
  }
}

function getMockStats() {
  const users = JSON.parse(fs.readFileSync(USERS_FILE, 'utf8')).filter(u => u.role !== 'admin');
  return users.map(u => ({
    name: `codeserver-${u.username}`,
    cpu: (Math.random() * 15).toFixed(1) + '%',
    mem: `${(Math.random() * 800 + 200).toFixed(0)}MiB / 56GiB`,
    memPerc: (Math.random() * 3).toFixed(1) + '%',
    net: `${(Math.random() * 10).toFixed(1)}MB / ${(Math.random() * 50).toFixed(1)}MB`,
    mock: true
  }));
}

function getDockerContainerStatus(username) {
  try {
    const status = execSync(
      `docker inspect --format='{{.State.Status}}' codeserver-${username}`,
      { timeout: 3000, encoding: 'utf8' }
    ).trim();
    return status;
  } catch {
    return 'not_found';
  }
}

router.get('/stats', requireAdmin, (req, res) => {
  const stats = getDockerStats();
  res.json({ stats, timestamp: new Date().toISOString() });
});

router.get('/users/status', requireAdmin, (req, res) => {
  const users = JSON.parse(fs.readFileSync(USERS_FILE, 'utf8'));
  const stats = getDockerStats();

  const result = users.filter(u => u.role !== 'admin').map(u => {
    const stat = stats.find(s => s.name === `codeserver-${u.username}`);
    const containerStatus = getDockerContainerStatus(u.username);
    return {
      id: u.id,
      username: u.username,
      displayName: u.displayName,
      port: u.port,
      projects: u.projects || [],
      createdAt: u.createdAt,
      container: {
        status: containerStatus,
        cpu: stat ? stat.cpu : '0%',
        mem: stat ? stat.mem : '0MiB / 0GiB',
        memPerc: stat ? stat.memPerc : '0%',
        net: stat ? stat.net : '0B / 0B',
        mock: stat ? !!stat.mock : true
      }
    };
  });

  res.json({ users: result, timestamp: new Date().toISOString() });
});

router.get('/db/info', requireAuth, (req, res) => {
  const username = req.session.user.username;
  res.json({
    postgresql: {
      host: 'devplatform-postgres',
      port: 5432,
      database: 'devplatform',
      schema: username,
      user: username,
      note: 'Akses langsung dari terminal VS Code-mu. Password dikasih admin.',
      example: `psql -h devplatform-postgres -U ${username} -d devplatform`
    },
    mysql: {
      host: 'devplatform-mysql',
      port: 3306,
      database: `db_${username}`,
      user: username,
      note: 'Akses langsung dari terminal VS Code-mu. Password dikasih admin.',
      example: `mysql -h devplatform-mysql -u ${username} -p db_${username}`
    },
    access: {
      from_codeserver: 'Langsung connect pakai hostname container di atas',
      from_browser: 'Buka Adminer di db-admin.' + (process.env.DOMAIN || 'domain-kamu'),
      from_laptop: 'SSH tunnel: ssh -L 5432:localhost:5432 user@vps-ip'
    }
  });
});

router.get('/projects/:username', requireAuth, (req, res) => {
  const { username } = req.params;
  if (req.session.user.role !== 'admin' && req.session.user.username !== username) {
    return res.status(403).json({ error: 'Forbidden' });
  }
  const users = JSON.parse(fs.readFileSync(USERS_FILE, 'utf8'));
  const user = users.find(u => u.username === username);
  if (!user) return res.status(404).json({ error: 'User tidak ditemukan' });

  const domain = process.env.DOMAIN || 'dev.domainmu.com';
  const protocol = process.env.PROTOCOL || 'http';
  const projects = (user.projects || ['default']).map(p => ({
    name: p,
    url: `${protocol}://${username}.${domain}/?folder=/config/projects/${p}`,
    localPort: `http://localhost:${user.port}/?folder=/config/projects/${p}`
  }));

  res.json({ username, projects });
});

module.exports = router;
