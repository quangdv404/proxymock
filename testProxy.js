// testProxy.js
const http = require('http');
const https = require('https');

const options = {
  host: '127.0.0.1',
  port: 9090,
  method: 'CONNECT',
  path: 'www.google.com:443',
};

console.log("Testing CONNECT proxy...");
const req = http.request(options);
req.end();

req.on('connect', (res, socket, head) => {
  console.log('Got CONNECT response! Status:', res.statusCode);
  
  // Now make an HTTPS request over the socket
  const agent = new https.Agent({ socket: socket });
  const httpsReq = https.request({
    host: 'www.google.com',
    port: 443,
    agent: agent,
    method: 'GET',
    path: '/',
    rejectUnauthorized: false
  }, (httpsRes) => {
    console.log("Got HTTPS response! Status:", httpsRes.statusCode);
  });
  
  httpsReq.on('error', (e) => {
    console.error("HTTPS request failed:", e);
  });
  httpsReq.end();
});

req.on('error', (e) => {
  console.error("CONNECT request failed:", e);
});
