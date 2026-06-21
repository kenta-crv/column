(function() {
  'use strict';

  function initEmbed() {
    const scripts = document.querySelectorAll('script[src*="embed.js"]');
    
    scripts.forEach(function(script) {
      const apiKey = script.dataset.apiKey;
      const containerId = script.dataset.containerId || 'articles';
      const container = document.getElementById(containerId);
      
      if (!container) {
        console.error('Container element not found: #' + containerId);
        return;
      }
      
      if (!apiKey) {
        console.error('API key not found in data-api-key attribute');
        return;
      }
      
      loadArticles(apiKey, container);
    });
  }

  function loadArticles(apiKey, container) {
    container.innerHTML = '<div class="embed-loading" style="padding:20px; text-align:center;">読み込み中...</div>';
    
    const urlParams = new URLSearchParams(window.location.search);
    const columnCode = urlParams.get('column');
    
    const apiEndpoint = determineApiEndpoint();
    let url = apiEndpoint + '/api/v1/articles/render_html?api_key=' + encodeURIComponent(apiKey);
    
    if (columnCode) {
      url += '&column=' + encodeURIComponent(columnCode);
    }
    
    fetch(url, {
      method: 'POST',
      headers: {
        'X-API-Key': apiKey
      }
    })
    .then(function(response) {
      return response.text();
    })
    .then(function(html) {
      if (html && html.trim() !== "") {
        container.innerHTML = html;
      } else {
        container.innerHTML = '<div class="embed-error">データを取得できませんでした。</div>';
      }
    })
    .catch(function(error) {
      console.error('Fetch operation error:', error);
      container.innerHTML = '<div class="embed-error">記事の読み込みに失敗しました。</div>';
    });
  }

  function determineApiEndpoint() {
    const scripts = document.querySelectorAll('script[src*="embed.js"]');
    if (scripts.length > 0) {
      const scriptSrc = scripts[0].src;
      const match = scriptSrc.match(/^(https?:\/\/[^\/]+)/);
      if (match) {
        return match[1];
      }
    }
    return window.location.origin;
  }

  // DOMContentLoadedを待たずに即時実行
  initEmbed();

})();