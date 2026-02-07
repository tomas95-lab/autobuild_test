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
  const icons = {
    success: `<svg class="w-6 h-6 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
              </svg>`,
    error: `<svg class="w-6 h-6 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"/>
            </svg>`,
    warning: `<svg class="w-6 h-6 text-yellow-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
              </svg>`,
    info: `<svg class="w-6 h-6 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
             <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
           </svg>`
  };

  const colors = {
    success: 'green',
    error: 'red',
    warning: 'yellow',
    info: 'blue'
  };
  
  const color = colors[type] || 'blue';
  const icon = icons[type] || icons.info;
  
  statusBanner.className = `mb-8 fade-in`;
  statusBanner.innerHTML = `
    <div class="card rounded-2xl shadow-xl p-5 border-l-4 border-${color}-500">
      <div class="flex items-center space-x-4">
        <div class="bg-${color}-100 p-3 rounded-xl">
          ${icon}
        </div>
        <div class="flex-1">
          <p class="font-semibold text-${color}-800 text-lg">${message}</p>
        </div>
      </div>
    </div>
  `;
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
    showStatus('Please select a task ZIP file', 'error');
    return;
  }
  
  if (!name) {
    showStatus('Please enter a task name', 'error');
    return;
  }
  
  if (!file.name.endsWith('.zip')) {
    showStatus('Task file must be a ZIP archive', 'error');
    return;
  }
  
  // Disable button
  runButton.disabled = true;
  runButton.innerHTML = `
    <div class="spinner"></div>
    <span>Uploading...</span>
  `;
  
  try {
    // Step 1: Upload via Vercel backend
    showStatus('Step 1/3: Uploading task to GitHub...', 'info');
    const releaseTag = await uploadViaBackend(file, name);
    
    // Step 2: Trigger workflow
    showStatus('Step 2/3: Triggering autobuild workflow...', 'info');
    await triggerAutobuildWorkflow(releaseTag, mode, keepArtifacts.checked);
    
    // Step 3: Monitor
    showStatus('Step 3/3: Monitoring execution...', 'success');
    showExecutionSection();
    startPolling();
    
  } catch (error) {
    console.error('Error:', error);
    showStatus(`Error: ${error.message}`, 'error');
    runButton.disabled = false;
    runButton.innerHTML = `
      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"/>
      </svg>
      <span>Run Autobuild</span>
    `;
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
    runButton.innerHTML = `
      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"/>
      </svg>
      <span>Run Autobuild</span>
    `;
  }
}

// Render workflow status
function renderWorkflowStatus(run) {
  const statusIcons = {
    success: `<svg class="w-10 h-10 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
              </svg>`,
    failure: `<svg class="w-10 h-10 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
               <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"/>
             </svg>`,
    in_progress: `<div class="spinner"></div>`,
    pending: `<svg class="w-10 h-10 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
              </svg>`
  };

  const statusColor = 
    run.status === 'completed' && run.conclusion === 'success' ? 'green' :
    run.status === 'completed' && run.conclusion === 'failure' ? 'red' :
    run.status === 'in_progress' ? 'purple' :
    'gray';
  
  const statusIcon =
    run.status === 'completed' && run.conclusion === 'success' ? statusIcons.success :
    run.status === 'completed' && run.conclusion === 'failure' ? statusIcons.failure :
    run.status === 'in_progress' ? statusIcons.in_progress :
    statusIcons.pending;
  
  executionSection.classList.remove('hidden');
  executionStatus.innerHTML = `
    <div class="bg-gradient-to-r from-${statusColor}-50 to-${statusColor}-100 rounded-2xl p-6 border-2 border-${statusColor}-200">
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-4">
          <div class="bg-${statusColor}-100 p-3 rounded-xl">
            ${statusIcon}
          </div>
          <div>
            <div class="text-2xl font-bold text-${statusColor}-900">
              ${run.status === 'completed' ? run.conclusion.toUpperCase() : run.status.toUpperCase().replace('_', ' ')}
            </div>
            <div class="text-sm text-${statusColor}-700 mt-1">
              Run #${run.run_number} - ${new Date(run.created_at).toLocaleString()}
            </div>
          </div>
        </div>
        <a href="${run.html_url}" target="_blank" 
           class="inline-flex items-center space-x-2 px-5 py-3 bg-${statusColor}-600 text-white font-semibold rounded-xl hover:bg-${statusColor}-700 transition shadow-lg">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"/>
          </svg>
          <span>View Workflow</span>
        </a>
      </div>
    </div>
  `;
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
  
  const statusIcon = run.conclusion === 'success' 
    ? `<svg class="w-10 h-10 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
         <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
       </svg>`
    : `<svg class="w-10 h-10 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
         <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"/>
       </svg>`;
  
  const statusColor = run.conclusion === 'success' ? 'green' : 'red';
  const duration = Math.floor((new Date(run.updated_at) - new Date(run.created_at)) / 1000 / 60);
  
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
    resultsContent.innerHTML = `
      <div class="bg-red-50 rounded-xl p-6 border-2 border-red-200">
        <div class="flex items-center space-x-3">
          <svg class="w-6 h-6 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
          </svg>
          <p class="text-red-800 font-semibold">Failed to load artifacts</p>
        </div>
      </div>
    `;
    return;
  }
  
  const artifactsData = await artifactsResponse.json();
  const artifacts = artifactsData.artifacts;
  
  resultsContent.innerHTML = `
    <div class="bg-gradient-to-r from-${statusColor}-50 to-${statusColor}-100 rounded-2xl p-8 mb-8 border-2 border-${statusColor}-200">
      <div class="flex items-center space-x-5">
        <div class="bg-${statusColor}-100 p-4 rounded-2xl">
          ${statusIcon}
        </div>
        <div class="flex-1">
          <h3 class="text-3xl font-bold text-${statusColor}-900 mb-2">
            ${run.conclusion === 'success' ? 'Execution Completed Successfully' : 'Execution Failed'}
          </h3>
          <p class="text-${statusColor}-700 font-medium">Status: ${run.conclusion}</p>
          <p class="text-sm text-${statusColor}-600 mt-2">Run #${run.run_number} - Completed ${new Date(run.updated_at).toLocaleString()}</p>
        </div>
      </div>
    </div>
    
    <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
      <div class="card rounded-xl p-6 hover-lift">
        <div class="flex items-center space-x-3 mb-3">
          <svg class="w-6 h-6 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
          </svg>
          <h4 class="font-bold text-gray-900">Duration</h4>
        </div>
        <p class="text-4xl font-bold text-blue-700">${duration}<span class="text-xl text-gray-600">min</span></p>
      </div>
      
      <div class="card rounded-xl p-6 hover-lift">
        <div class="flex items-center space-x-3 mb-3">
          <svg class="w-6 h-6 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"/>
          </svg>
          <h4 class="font-bold text-gray-900">Artifacts</h4>
        </div>
        <p class="text-4xl font-bold text-purple-700">${artifacts.length}</p>
      </div>
      
      <div class="card rounded-xl p-6 hover-lift">
        <div class="flex items-center space-x-3 mb-3">
          <svg class="w-6 h-6 text-indigo-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"/>
          </svg>
          <h4 class="font-bold text-gray-900">View Full Log</h4>
        </div>
        <a href="${run.html_url}" target="_blank" 
           class="inline-flex items-center space-x-2 text-indigo-600 hover:text-indigo-800 font-semibold mt-2">
          <span>Open Workflow</span>
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14 5l7 7m0 0l-7 7m7-7H3"/>
          </svg>
        </a>
      </div>
    </div>
  `;
  
  if (artifacts.length === 0) {
    resultsContent.innerHTML += `
      <div class="card rounded-xl p-8 text-center">
        <svg class="w-16 h-16 text-gray-400 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"/>
        </svg>
        <p class="text-gray-600 font-medium">No artifacts were generated</p>
      </div>
    `;
    return;
  }
  
  // Render artifacts
  resultsContent.innerHTML += `
    <div class="card rounded-xl p-6">
      <div class="flex items-center space-x-3 mb-6">
        <svg class="w-6 h-6 text-gray-700" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
        </svg>
        <h4 class="text-xl font-bold text-gray-800">Generated Artifacts</h4>
      </div>
      <div class="space-y-3">
        ${artifacts.map(artifact => `
          <div class="flex items-center justify-between p-5 border-2 border-gray-200 rounded-xl hover:border-purple-300 hover:shadow-md transition">
            <div class="flex items-center space-x-4">
              <div class="bg-purple-100 p-3 rounded-lg">
                <svg class="w-6 h-6 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                </svg>
              </div>
              <div>
                <div class="font-semibold text-gray-900">${artifact.name}</div>
                <div class="text-sm text-gray-600 mt-1">
                  ${(artifact.size_in_bytes / 1024 / 1024).toFixed(2)} MB - 
                  Expires ${new Date(artifact.expires_at).toLocaleDateString()}
                </div>
              </div>
            </div>
            <button onclick="downloadArtifact(${artifact.id}, '${artifact.name}')" 
                    class="inline-flex items-center space-x-2 px-5 py-3 bg-purple-600 text-white font-semibold rounded-xl hover:bg-purple-700 transition shadow-lg">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"/>
              </svg>
              <span>Download</span>
            </button>
          </div>
        `).join('')}
      </div>
    </div>
  `;
}
              </div>
              <button onclick="downloadArtifact(${artifact.id}, '${artifact.name}')" 
                 class="px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 transition">
                📥 Download
              </button>
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

// Download artifact with proper authentication
async function downloadArtifact(artifactId, name) {
  try {
    showStatus('Downloading artifact...', 'info');
    
    const response = await fetch(
      `https://api.github.com/repos/${CONFIG.owner}/${CONFIG.repo}/actions/artifacts/${artifactId}/zip`,
      {
        headers: {
          'Authorization': `token ${CONFIG.token}`,
          'Accept': 'application/vnd.github.v3+json'
        }
      }
    );
    
    if (!response.ok) {
      throw new Error(`Failed to download: ${response.status}`);
    }
    
    const blob = await response.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.style.display = 'none';
    a.href = url;
    a.download = `${name}.zip`;
    document.body.appendChild(a);
    a.click();
    window.URL.revokeObjectURL(url);
    document.body.removeChild(a);
    
    showStatus('Artifact downloaded successfully!', 'success');
  } catch (error) {
    showStatus(`Download failed: ${error.message}`, 'error');
      }
    );
    
    if (!response.ok) {
      throw new Error(`Download failed: ${response.statusText}`);
    }
    
    const blob = await response.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${name}.zip`;
    document.body.appendChild(a);
    a.click();
    window.URL.revokeObjectURL(url);
    document.body.removeChild(a);
    
    showStatus('Artifact downloaded successfully!', 'success');
  } catch (error) {
    console.error('Download error:', error);
    showStatus(`Download failed: ${error.message}`, 'error');
  }
}
