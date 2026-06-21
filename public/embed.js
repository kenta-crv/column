(function() {
  'use strict';

  function initEmbed() {
    const scripts = document.querySelectorAll('script[src*="embed.js"]');
    
    scripts.forEach(function(script) {
      // 💡 ページ遷移のたびに再実行できるよう、一度実行したタグでもコンテナが空なら再処理する
      const apiKey = script.dataset.apiKey;
      const containerId = script.dataset.containerId || 'articles';
      const container = document.getElementById(containerId);
      
      if (!container) return;
      
      // すでに読み込み中、または取得済みの場合は重複実行を防ぐ
      if (container.dataset.embeddedLoaded === 'true') return;
      if (!apiKey) return;
      
      container.dataset.embeddedLoaded = 'true';
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
        container.dataset.embeddedLoaded = 'false';
      }
    })
    .catch(function(error) {
      container.innerHTML = '<div class="embed-error">記事の読み込みに失敗しました。</div>';
      container.dataset.embeddedLoaded = 'false';
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

  // 1. 通常の初回読み込み時の実行
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initEmbed);
  } else {
    initEmbed();
  }

  // 2. 💡 RailsのTurbolinksによるページ遷移（更新）を監視して強制再実行
  document.addEventListener('turbolinks:load', initEmbed);

})();