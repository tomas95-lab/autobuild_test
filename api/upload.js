// Vercel Serverless Function - Upload task to GitHub

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
    
    // 2. Upload ZIP as asset (fix Windows backslashes)
    const uploadUrl = release.upload_url.replace('{?name,label}', `?name=${encodeURIComponent(taskName)}.zip`);
    let fileBuffer = Buffer.from(file, 'base64');
    
    // Fix Windows paths in ZIP (convert backslashes to forward slashes)
    // This is a workaround for ZIPs created on Windows
    try {
      const JSZip = (await import('jszip')).default;
      const zip = await JSZip.loadAsync(fileBuffer);
      const newZip = new JSZip();
      
      // Copy all files with Unix-style paths
      for (const [path, zipEntry] of Object.entries(zip.files)) {
        if (!zipEntry.dir) {
          const unixPath = path.replace(/\\/g, '/');
          const content = await zipEntry.async('nodebuffer');
          newZip.file(unixPath, content);
        }
      }
      
      // Generate new ZIP with correct paths
      fileBuffer = await newZip.generateAsync({ 
        type: 'nodebuffer',
        compression: 'DEFLATE',
        compressionOptions: { level: 6 }
      });
      
      console.log('ZIP paths fixed for Unix compatibility');
    } catch (error) {
      console.warn('Could not fix ZIP paths:', error.message);
      // Continue with original ZIP if fix fails
    }
    
    console.log('Upload URL:', uploadUrl);
    console.log('File size:', fileBuffer.length);
    
    const uploadResponse = await fetch(uploadUrl, {
      method: 'POST',
      headers: {
        'Authorization': `token ${token}`,
        'Content-Type': 'application/zip',
        'Content-Length': String(fileBuffer.length),
        'Accept': 'application/vnd.github.v3+json'
      },
      body: fileBuffer
    });
    
    if (!uploadResponse.ok) {
      const errorText = await uploadResponse.text();
      console.error('Upload failed:', errorText);
      throw new Error(`Failed to upload asset: ${uploadResponse.status} ${uploadResponse.statusText} - ${errorText}`);
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
