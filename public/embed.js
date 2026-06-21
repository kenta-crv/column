(function() {
  'use strict';

  function scanAndEmbed() {
    const scripts = document.querySelectorAll('script[src*="embed.js"]');
    
    scripts.forEach(function(script) {
      // すでに処理済みのスクリプトはスキップ
      if (script.dataset.embedded === 'true') return;

      const apiKey = script.dataset.apiKey;
      const containerId = script.dataset.containerId || 'articles';
      const container = document.getElementById(containerId);
      
      // コンテナ要素がDOM上にまだ存在しない場合はスキップして次の監視に委ねる
      if (!container) return;
      
      if (!apiKey) {
        console.error('API key not found in data-api-key attribute');
        script.dataset.embedded = 'true';
        return;
      }
      
      // 処理開始フラグを立てて実行
      script.dataset.embedded = 'true';
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

  // 1. スクリプト読み込み時点での即時実行を試行
  scanAndEmbed();

  // 2. 3002番側のSlimレンダリング完了を検知するため、DOMの動的変化を自動監視
  if (typeof MutationObserver !== 'undefined') {
    const observer = new MutationObserver(function() {
      scanAndEmbed();
    });
    observer.observe(document.documentElement, {
      childList: true,
      subtree: true
    });
  }
})();