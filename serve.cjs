const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname);
const port = Number(process.env.MOUNTAINMARK_WEB_PORT || 8077);
const mime = {'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png','.svg':'image/svg+xml','.ico':'image/x-icon','.json':'application/json'};
if (!fs.existsSync(path.join(root, 'index.html'))) { console.error('Missing MountainMark/index.html. Run build.ps1 first.'); process.exit(1); }
const server = http.createServer((req,res) => {
 let name;
 try { name = decodeURIComponent(new URL(req.url, 'http://localhost').pathname); } catch { res.writeHead(400); res.end(); return; }
 const file = path.resolve(root, '.' + (name === '/' ? '/index.html' : name));
 if (!file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
 fs.stat(file,(error,stat) => {
  if (error || !stat.isFile()) {res.writeHead(404);res.end('Not found');return;}
  res.writeHead(200, {'Content-Type':mime[path.extname(file)] || 'application/octet-stream','Content-Length':stat.size,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
  if (req.method === 'HEAD') res.end(); else fs.createReadStream(file).pipe(res);
 });
});
server.on('error', error => {console.error(error.message);process.exitCode=1;});
server.listen(port,'127.0.0.1',()=>{
 const url='http://127.0.0.1:'+port+'/index.html';
 console.log('Mountain Mark: '+url+' (Ctrl+C to stop)');
 if(process.argv.includes('--open')) require('node:child_process').spawn('explorer.exe',[url],{windowsHide:true,stdio:'ignore'}).on('error',error=>console.error('Open this address in your browser: '+url+' ('+error.message+')'));
});
