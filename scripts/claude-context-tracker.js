#!/usr/bin/env node

const fs = require('fs').promises;
const path = require('path');

// Standard Claude context window limits (in tokens)
const CONTEXT_LIMITS = {
  'claude-sonnet-4-5-20250929': 1000000,
  'claude-haiku-4-5-20250929': 1000000,
  'claude-sonnet-4-20250514': 1000000,
  'claude-opus-4-1-20250805': 200000,
  'claude-haiku-4-20250514': 200000,
  'claude-3-5-sonnet-20241022': 200000,
  'claude-3-5-haiku-20241022': 200000,
  'claude-3-opus-20240229': 200000,
  'default': 200000
};

// Helper function to get context limit for a model
function getContextLimit(modelId) {
  return CONTEXT_LIMITS[modelId] || CONTEXT_LIMITS.default;
}

// Helper function to format numbers in K/M format
function formatTokenCount(tokens) {
  if (tokens >= 1000000) {
    const millions = tokens / 1000000;
    return millions === 1 ? '1M' : millions.toFixed(1) + 'M';
  } else if (tokens >= 1000) {
    return (tokens / 1000).toFixed(1) + 'K';
  }
  return tokens.toString();
}

// Find current session start boundary (last parentUuid: null)
function findCurrentSessionStart(lines) {
  let lastBoundary = 0;
  for (let i = 0; i < lines.length; i++) {
    try {
      const data = JSON.parse(lines[i].trim());
      if (data.parentUuid === null) {
        lastBoundary = i + 1; // Start after the boundary
      }
    } catch {
      continue;
    }
  }
  return lastBoundary;
}

// Calculate context window using enhanced algorithm
async function calculateContextWindow(filePath, startFromLine = 0) {
  const totals = {
    input: 0, output: 0, cache_creation: 0,
    cache_read: 0, ephemeral_5m: 0, ephemeral_1h: 0
  };
  const skippedTotals = {
    input: 0, output: 0, cache_creation: 0,
    cache_read: 0, ephemeral_5m: 0, ephemeral_1h: 0
  };
  
  let entriesCount = 0;
  let skippedCount = 0;
  let latestCacheRead = 0;
  let latestSkippedCacheRead = 0;
  let modelId = 'unknown';
  
  try {
    const content = await fs.readFile(filePath, 'utf-8');
    const allLines = content.trim().split('\n').filter(line => line.length > 0);
    
    // FIRST PASS: Find LAST occurrence of each request ID
    const requestIdToLastLine = {};
    for (let lineIdx = startFromLine; lineIdx < allLines.length; lineIdx++) {
      try {
        const data = JSON.parse(allLines[lineIdx].trim());
        if (data.type === 'assistant' && data.message) {
          const requestId = data.requestId || '';
          if (requestId) {
            requestIdToLastLine[requestId] = lineIdx;
          }
        }
      } catch {
        continue;
      }
    }
    
    // SECOND PASS: Process entries, keeping only LAST occurrence per request ID
    for (let lineIdx = startFromLine; lineIdx < allLines.length; lineIdx++) {
      try {
        const data = JSON.parse(allLines[lineIdx].trim());
        
        // Only process assistant messages with tokens
        if (data.type === 'assistant' && data.message) {
          const requestId = data.requestId || '';
          
          // Check if this is the LAST occurrence
          let isLastOccurrence = true;
          if (requestId && requestId in requestIdToLastLine) {
            isLastOccurrence = (lineIdx === requestIdToLastLine[requestId]);
          }
          
          const usage = data.message.usage || {};
          
          if (!isLastOccurrence) {
            // SKIPPED: Earlier streaming response
            skippedCount++;
            if (usage.input_tokens) skippedTotals.input += usage.input_tokens;
            if (usage.output_tokens) skippedTotals.output += usage.output_tokens;
            if (usage.cache_creation_input_tokens) skippedTotals.cache_creation += usage.cache_creation_input_tokens;
            if (usage.cache_read_input_tokens && usage.cache_read_input_tokens > 0) {
              latestSkippedCacheRead = usage.cache_read_input_tokens;
            }
            
            // Track ephemeral cache breakdown for skipped
            const cacheCreation = usage.cache_creation || {};
            if (cacheCreation.ephemeral_5m_input_tokens) skippedTotals.ephemeral_5m += cacheCreation.ephemeral_5m_input_tokens;
            if (cacheCreation.ephemeral_1h_input_tokens) skippedTotals.ephemeral_1h += cacheCreation.ephemeral_1h_input_tokens;
          } else {
            // COUNTED: Final streaming response
            entriesCount++;
            if (usage.input_tokens) totals.input += usage.input_tokens;
            if (usage.output_tokens) totals.output += usage.output_tokens;
            if (usage.cache_creation_input_tokens) totals.cache_creation += usage.cache_creation_input_tokens;
            if (usage.cache_read_input_tokens && usage.cache_read_input_tokens > 0) {
              latestCacheRead = usage.cache_read_input_tokens;
            }
            
            // Track ephemeral cache breakdown
            const cacheCreation = usage.cache_creation || {};
            if (cacheCreation.ephemeral_5m_input_tokens) totals.ephemeral_5m += cacheCreation.ephemeral_5m_input_tokens;
            if (cacheCreation.ephemeral_1h_input_tokens) totals.ephemeral_1h += cacheCreation.ephemeral_1h_input_tokens;
            
            // Track model
            if (data.message.model && data.message.model !== 'unknown') {
              modelId = data.message.model;
            }
          }
        }
      } catch {
        continue;
      }
    }
  } catch (err) {
    console.error(`Error reading transcript file: ${err.message}`);
    return null;
  }
  
  // Calculate final totals using validated formula
  const countedTotal = totals.input + totals.cache_creation + latestCacheRead + totals.output;
  const skippedTotal = skippedTotals.input + skippedTotals.cache_creation + latestSkippedCacheRead + skippedTotals.output;
  const realisticTotal = countedTotal + (skippedTotal - skippedTotals.cache_creation);
  
  return {
    countedTotal,
    skippedTotal,
    realisticTotal,
    entriesProcessed: entriesCount,
    entriesSkipped: skippedCount,
    totals,
    skippedTotals,
    latestCacheRead,
    latestSkippedCacheRead,
    model: modelId
  };
}

// Legacy function kept for compatibility but not used
function calculateContextStats(entries) {
  // This function is now replaced by calculateContextWindow
  return null;
}

// Main function
async function main() {
  try {
    // Read Claude Code context from stdin
    let input = '';
    process.stdin.setEncoding('utf8');
    
    for await (const chunk of process.stdin) {
      input += chunk;
    }

    if (!input.trim()) {
      console.error('No input provided');
      process.exit(1);
    }

    const claudeInput = JSON.parse(input);
    const { session_id, transcript_path } = claudeInput;

    if (!session_id || !transcript_path) {
      console.error('Missing session_id or transcript_path in input');
      process.exit(1);
    }

    // Check if transcript file exists
    try {
      await fs.access(transcript_path);
    } catch {
      console.error(`Transcript file not found: ${transcript_path}`);
      process.exit(1);
    }

    // Calculate context window with enhanced algorithm
    const content = await fs.readFile(transcript_path, 'utf-8');
    const lines = content.trim().split('\n').filter(line => line.length > 0);
    const startLine = findCurrentSessionStart(lines);
    
    const result = await calculateContextWindow(transcript_path, startLine);
    
    if (!result) {
      console.error('Failed to calculate context window');
      process.exit(1);
    }
    
    const contextLimit = getContextLimit(result.model);
    const contextUsagePercent = Math.round((result.realisticTotal / contextLimit) * 100);
    
    // Output format for statusline parsing
    console.log(`Session: ${session_id}`);
    console.log(`Model: ${result.model}`);
    console.log(`Context usage: ${formatTokenCount(result.realisticTotal)}/${formatTokenCount(contextLimit)} tokens (${contextUsagePercent}%)`);
    console.log(`Messages processed: ${result.entriesProcessed}`);
    console.log(`Messages skipped: ${result.entriesSkipped}`);

  } catch (err) {
    console.error(`Error: ${err.message}`);
    process.exit(1);
  }
}

// Run the script
main().catch(err => {
  console.error('Unexpected error:', err.message);
  process.exit(1);
});