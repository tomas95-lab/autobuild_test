// Vercel Serverless Function - Upload task to GitHub
import fetch from 'node-fetch';

export default async function handler(req, res) {
  // CORS headers
  res.setHeader('Access-Control-Allow-Credentials', true);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS,PATCH,DELETE,POST,PUT');
  res.setHeader('Access-Control-Allow-Headers', 'X-CSRF-Token, X-Requested-With, Accept, Accept-Version, Content-Length, Content-MD5, Content-Type, Date, X-Api-Version, Authorization');
  
  if (req.method === 'OPTIONS') {
    res.status(200).end();
    return;
  }
  
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }
  
  try {
    const { file, taskName, token, owner, repo } = req.body;
    
    if (!file || !taskName || !token || !owner || !repo) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    
    const tag = `task-${taskName}-${Date.now()}`;
    
    // 1. Create GitHub release
    const releaseResponse = await fetch(
      `https://api.github.com/repos/${owner}/${repo}/releases`,
      {
        method: 'POST',
        headers: {
          'Authorization': `token ${token}`,
          'Content-Type': 'application/json',
          'Accept': 'application/vnd.github.v3+json'
        },
        body: JSON.stringify({
          tag_name: tag,
          name: `Task: ${taskName}`,
          body: `Autobuild task upload - ${new Date().toISOString()}`,
          draft: false,
          prerelease: true
        })
      }
    );
    
    if (!releaseResponse.ok) {
      const error = await releaseResponse.json();
      throw new Error(`Failed to create release: ${error.message}`);
    }
    
    const release = await releaseResponse.json();
    
    // 2. Upload ZIP as asset
    const uploadUrl = release.upload_url.replace('{?name,label}', `?name=${taskName}.zip`);
    const fileBuffer = Buffer.from(file, 'base64');
    
    const uploadResponse = await fetch(uploadUrl, {
      method: 'POST',
      headers: {
        'Authorization': `token ${token}`,
        'Content-Type': 'application/zip',
        'Content-Length': fileBuffer.length
      },
      body: fileBuffer
    });
    
    if (!uploadResponse.ok) {
      throw new Error(`Failed to upload asset: ${uploadResponse.statusText}`);
    }
    
    const asset = await uploadResponse.json();
    
    // 3. Return success with tag
    return res.status(200).json({
      success: true,
      releaseTag: tag,
      releaseUrl: release.html_url,
      assetUrl: asset.browser_download_url
    });
    
  } catch (error) {
    console.error('Upload error:', error);
    return res.status(500).json({ error: error.message });
  }
}
