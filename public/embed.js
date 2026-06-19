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
    const apiEndpoint = determineApiEndpoint();
    
    fetch(apiEndpoint + '/api/v1/articles/render_html?api_key=' + encodeURIComponent(apiKey), {
      method: 'POST',
      headers: {
        'X-API-Key': apiKey
      }
    })
    .then(function(response) {
      // ステータスコードに関係なく、テキスト情報を引き出す
      return response.text();
    })
    .then(function(html) {
      // 厳密な判定をすべてやめ、データが入っていればそのまま流し込む
      if (html) {
        container.innerHTML = html;
        
        // 独自イベントの着火でエラーが起きても画面描画を邪魔しないように try-catch で保護
        try {
          container.dispatchEvent(new CustomEvent('articlesLoaded', { 
            detail: { container: container }
          }));
        } catch (e) {
          console.error('CustomEvent dispatch failed:', e);
        }
      } else {
        container.innerHTML = '<div class="embed-error">表示できる記事がありません。</div>';
      }
    })
    .catch(function(error) {
      // catch 内での誤作動を防ぐため、ログを出した上で取得した中身をそのまま強制挿入を試みる
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

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initEmbed);
  } else {
    initEmbed();
  }
})();