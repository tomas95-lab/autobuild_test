// Configuration
const CONFIG = {
  owner: 'tomas95-lab',
  repo: 'autobuild_test',
  token: localStorage.getItem('github_token') || null,
  // Vercel API endpoint (se configura después del deploy)
  apiUrl: window.location.hostname === 'localhost' 
    ? 'http://localhost:3000/api'
    : '/api'
};

// State
let currentWorkflowRun = null;
let pollInterval = null;

// DOM Elements
const taskFile = document.getElementById('taskFile');
const taskName = document.getElementById('taskName');
const executionMode = document.getElementById('executionMode');
const keepArtifacts = document.getElementById('keepArtifacts');
const runButton = document.getElementById('runButton');
const statusBanner = document.getElementById('statusBanner');
const executionSection = document.getElementById('executionSection');
const executionStatus = document.getElementById('executionStatus');
const resultsSection = document.getElementById('resultsSection');
const resultsContent = document.getElementById('resultsContent');
const secretsLink = document.getElementById('secretsLink');

// Initialize
document.addEventListener('DOMContentLoaded', () => {
  // Set GitHub secrets link
  secretsLink.href = `https://github.com/${CONFIG.owner}/${CONFIG.repo}/settings/secrets/actions`;
  
  // Check if token is set
  if (!CONFIG.token) {
    promptForToken();
  }
  
  // Add event listeners
  runButton.addEventListener('click', handleRun);
  
  // Generate random task name
  taskName.value = `task-${Date.now()}`;
});

// Token management
function promptForToken() {
  const token = prompt(
    'Enter your GitHub Personal Access Token (PAT):\n\n' +
    'Required scopes: repo, workflow\n' +
    'Create at: https://github.com/settings/tokens\n\n' +
    'Your token will be stored in localStorage (browser only)'
  );
  
  if (token) {
    CONFIG.token = token;
    localStorage.setItem('github_token', token);
    showStatus('Token saved! You can now run workflows.', 'success');
  } else {
    showStatus('Token required to trigger workflows. Some features will be limited.', 'warning');
  }
}

// Show status banner
function showStatus(message, type = 'info') {
  statusBanner.className = `mb-6 p-4 rounded-lg ${
    type === 'success' ? 'bg-green-100 text-green-800 border border-green-300' :
    type === 'error' ? 'bg-red-100 text-red-800 border border-red-300' :
    type === 'warning' ? 'bg-yellow-100 text-yellow-800 border border-yellow-300' :
    'bg-blue-100 text-blue-800 border border-blue-300'
  }`;
  statusBanner.textContent = message;
  statusBanner.classList.remove('hidden');
  
  // Auto-hide after 5 seconds for non-error messages
  if (type !== 'error') {
    setTimeout(() => {
      statusBanner.classList.add('hidden');
    }, 5000);
  }
}

// Handle run button click
async function handleRun() {
  if (!CONFIG.token) {
    promptForToken();
    if (!CONFIG.token) return;
  }
  
  const file = taskFile.files[0];
  const name = taskName.value.trim();
  const mode = executionMode.value;
  
  // Validation
  if (!file) {
    showStatus('❌ Please select a task ZIP file', 'error');
    return;
  }
  
  if (!name) {
    showStatus('❌ Please enter a task name', 'error');
    return;
  }
  
  if (!file.name.endsWith('.zip')) {
    showStatus('❌ Task file must be a ZIP archive', 'error');
    return;
  }
  
  // Disable button
  runButton.disabled = true;
  runButton.textContent = '⏳ Uploading...';
  
  try {
    // Step 1: Upload via Vercel backend
    showStatus('📤 Step 1/3: Uploading task to GitHub...', 'info');
    const releaseTag = await uploadViaBackend(file, name);
    
    // Step 2: Trigger workflow
    showStatus('🚀 Step 2/3: Triggering autobuild workflow...', 'info');
    await triggerAutobuildWorkflow(releaseTag, mode, keepArtifacts.checked);
    
    // Step 3: Monitor
    showStatus('👀 Step 3/3: Monitoring execution...', 'success');
    showExecutionSection();
    startPolling();
    
  } catch (error) {
    console.error('Error:', error);
    showStatus(`❌ Error: ${error.message}`, 'error');
    runButton.disabled = false;
    runButton.textContent = '🚀 Run Autobuild';
  }
}

// Upload via Vercel backend (avoids CORS)
async function uploadViaBackend(file, taskName) {
  // Convert file to base64
  const base64 = await fileToBase64(file);
  
  console.log('Uploading to backend...', {
    taskName,
    fileSize: file.size,
    base64Length: base64.length
  });
  
  const response = await fetch(`${CONFIG.apiUrl}/upload`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      file: base64,
      taskName: taskName,
      token: CONFIG.token,
      owner: CONFIG.owner,
      repo: CONFIG.repo
    })
  });
  
  console.log('Backend response status:', response.status);
  
  if (!response.ok) {
    const errorText = await response.text();
    console.error('Backend error:', errorText);
    
    // Try to parse as JSON for better error message
    try {
      const errorJson = JSON.parse(errorText);
      throw new Error(errorJson.error || errorJson.message || 'Upload failed');
    } catch {
      throw new Error(`Upload failed: ${response.status} - ${errorText.substring(0, 200)}`);
    }
  }
  
  const data = await response.json();
  console.log('Upload successful:', data);
  return data.releaseTag;
}

// Helper: convert file to base64
function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const base64 = reader.result.split(',')[1];
      resolve(base64);
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

// Trigger autobuild workflow (simplified - no upload needed)
async function triggerAutobuildWorkflow(releaseTag, mode, keepArtifacts) {
  const response = await fetch(
    `https://api.github.com/repos/${CONFIG.owner}/${CONFIG.repo}/actions/workflows/autobuild-v2.yml/dispatches`,
    {
      method: 'POST',
      headers: {
        'Authorization': `token ${CONFIG.token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        ref: 'main',
        inputs: {
          mode: mode,
          release_tag: releaseTag,
          keep_artifacts: keepArtifacts.toString()
        }
      })
    }
  );
  
  if (!response.ok) {
    throw new Error(`Failed to trigger workflow: ${response.statusText}`);
  }
  
  // Wait a bit for workflow to start
  await new Promise(resolve => setTimeout(resolve, 3000));
  
  // Get the latest workflow run
  const runsResponse = await fetch(
    `https://api.github.com/repos/${CONFIG.owner}/${CONFIG.repo}/actions/workflows/autobuild-v2.yml/runs?per_page=1`,
    {
      headers: {
        'Authorization': `token ${CONFIG.token}`,
      }
    }
  );
  
  if (!runsResponse.ok) {
    throw new Error(`Failed to fetch workflow runs: ${runsResponse.statusText}`);
  }
  
  const runsData = await runsResponse.json();
  currentWorkflowRun = runsData.workflow_runs[0];
}

// Show execution section
function showExecutionSection() {
  executionSection.classList.remove('hidden');
  resultsSection.classList.add('hidden');
}

// Start polling for workflow status
function startPolling() {
  if (pollInterval) {
    clearInterval(pollInterval);
  }
  
  pollInterval = setInterval(async () => {
    try {
      await updateWorkflowStatus();
    } catch (error) {
      console.error('Polling error:', error);
    }
  }, 5000); // Poll every 5 seconds
  
  // Initial update
  updateWorkflowStatus();
}

// Stop polling
function stopPolling() {
  if (pollInterval) {
    clearInterval(pollInterval);
    pollInterval = null;
  }
}

// Update workflow status
async function updateWorkflowStatus() {
  if (!currentWorkflowRun) return;
  
  const response = await fetch(
    `https://api.github.com/repos/${CONFIG.owner}/${CONFIG.repo}/actions/runs/${currentWorkflowRun.id}`,
    {
      headers: {
        'Authorization': `token ${CONFIG.token}`,
      }
    }
  );
  
  if (!response.ok) {
    console.error('Failed to fetch workflow status');
    return;
  }
  
  const run = await response.json();
  currentWorkflowRun = run;
  
  // Update UI
  renderWorkflowStatus(run);
  
  // Check if completed
  if (run.status === 'completed') {
    stopPolling();
    await loadResults(run);
    runButton.disabled = false;
    runButton.textContent = '🚀 Run Autobuild';
  }
}

// Render workflow status
function renderWorkflowStatus(run) {
  const statusColor = 
    run.status === 'completed' && run.conclusion === 'success' ? 'green' :
    run.status === 'completed' && run.conclusion === 'failure' ? 'red' :
    run.status === 'in_progress' ? 'blue' :
    'gray';
  
  const statusEmoji =
    run.status === 'completed' && run.conclusion === 'success' ? '✅' :
    run.status === 'completed' && run.conclusion === 'failure' ? '❌' :
    run.status === 'in_progress' ? '⏳' :
    '⏸️';
  
  executionStatus.innerHTML = `
    <div class="flex items-center space-x-4 p-4 bg-${statusColor}-50 rounded-lg border border-${statusColor}-200">
      <div class="text-3xl">${statusEmoji}</div>
      <div class="flex-1">
        <div class="font-bold text-${statusColor}-800">
          ${run.status === 'completed' ? run.conclusion.toUpperCase() : run.status.toUpperCase()}
        </div>
        <div class="text-sm text-gray-600">
          Run #${run.run_number} - ${new Date(run.created_at).toLocaleString()}
        </div>
      </div>
      <a href="${run.html_url}" target="_blank" 
         class="px-4 py-2 bg-${statusColor}-600 text-white rounded-lg hover:bg-${statusColor}-700 transition">
        View on GitHub
      </a>
    </div>
    
    ${run.status === 'in_progress' ? `
      <div class="flex justify-center py-4">
        <div class="spinner"></div>
      </div>
      <p class="text-center text-gray-600">
        Execution in progress... This may take several minutes.
      </p>
    ` : ''}
  `;
}

// Load results
async function loadResults(run) {
  resultsSection.classList.remove('hidden');
  
  // Fetch artifacts
  const artifactsResponse = await fetch(
    `https://api.github.com/repos/${CONFIG.owner}/${CONFIG.repo}/actions/runs/${run.id}/artifacts`,
    {
      headers: {
        'Authorization': `token ${CONFIG.token}`,
      }
    }
  );
  
  if (!artifactsResponse.ok) {
    resultsContent.innerHTML = '<p class="text-red-600">Failed to load artifacts</p>';
    return;
  }
  
  const artifactsData = await artifactsResponse.json();
  const artifacts = artifactsData.artifacts;
  
  if (artifacts.length === 0) {
    resultsContent.innerHTML = '<p class="text-gray-600">No artifacts generated</p>';
    return;
  }
  
  // Render artifacts
  resultsContent.innerHTML = `
    <div class="space-y-4">
      <h3 class="text-lg font-bold text-gray-800">Generated Artifacts</h3>
      ${artifacts.map(artifact => `
        <div class="flex items-center justify-between p-4 border rounded-lg hover:bg-gray-50">
          <div>
            <div class="font-medium">${artifact.name}</div>
            <div class="text-sm text-gray-500">
              ${(artifact.size_in_bytes / 1024 / 1024).toFixed(2)} MB - 
              Expires: ${new Date(artifact.expires_at).toLocaleDateString()}
            </div>
          </div>
          <a href="${artifact.archive_download_url}" 
             class="px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 transition">
            📥 Download
          </a>
        </div>
      `).join('')}
    </div>
    
    <div class="mt-6 p-4 bg-blue-50 rounded-lg border border-blue-200">
      <h4 class="font-bold text-blue-800 mb-2">Next Steps</h4>
      <ul class="text-sm text-blue-700 space-y-1">
        <li>• Download the artifacts to review logs</li>
        <li>• Check the workflow page for detailed execution logs</li>
        <li>• Artifacts are kept for 30 days</li>
      </ul>
    </div>
  `;
}

// Helper: Format bytes
function formatBytes(bytes) {
  if (bytes === 0) return '0 Bytes';
  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
}
