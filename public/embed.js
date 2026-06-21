(function() {
  'use strict';

  console.log('[embed.js] スクリプトファイル自体がブラウザに読み込まれました。');

  function scanAndEmbed() {
    const scripts = document.querySelectorAll('script[src*="embed.js"]');
    console.log('[embed.js] 画面内から検索された embed.js タグの数:', scripts.length);
    
    scripts.forEach(function(script, index) {
      console.log(`[embed.js] [タグ #${index}] 検証中... src:`, script.src);

      if (script.dataset.embedded === 'true') {
        console.log(`[embed.js] [タグ #${index}] すでに処理済み（embedded === true）のためスキップします。`);
        return;
      }

      const apiKey = script.dataset.apiKey;
      const containerId = script.dataset.containerId || 'articles';
      const container = document.getElementById(containerId);
      
      console.log(`[embed.js] [タグ #${index}] 設定情報 - apiKey:`, apiKey, '- containerId:', containerId);

      if (!container) {
        console.log(`[embed.js] [タグ #${index}] ❌ 警告: 画面内に #${containerId} という要素が見つかりません。一時スキップします。`);
        return;
      }
      
      if (!apiKey) {
        console.error(`[embed.js] [タグ #${index}] ❌ エラー: data-api-key が設定されていません。`);
        script.dataset.embedded = 'true';
        return;
      }
      
      console.log(`[embed.js] [タグ #${index}] 成功: コンテナ要素が見つかりました。APIリクエストを開始します。`);
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
    
    console.log('[embed.js] 実際に送信するFetchリクエスト先URL:', url);
    
    fetch(url, {
      method: 'POST',
      headers: {
        'X-API-Key': apiKey
      }
    })
    .then(function(response) {
      console.log('[embed.js] サーバーからレスポンスを受信しました。ステータスコード:', response.status);
      return response.text();
    })
    .then(function(html) {
      console.log('[embed.js] 受信したHTMLの文字数:', html ? html.length : 0);
      if (html && html.trim() !== "") {
        container.innerHTML = html;
        console.log('[embed.js] コンテナへのHTML挿入が完了しました。');
      } else {
        container.innerHTML = '<div class="embed-error">データを取得できませんでした。</div>';
        console.log('[embed.js] ❌ 警告: サーバーから空のHTMLが返されました。');
      }
    })
    .catch(function(error) {
      console.error('[embed.js] ❌ Fetch通信中に例外エラーが発生しました:', error);
      container.innerHTML = '<div class="embed-error">記事の読み込みに失敗しました。</div>';
    });
  }

  function determineApiEndpoint() {
    const scripts = document.querySelectorAll('script[src*="embed.js"]');
    if (scripts.length > 0) {
      const scriptSrc = scripts[0].src;
      const match = scriptSrc.match(/^(https?:\/\/[^\/]+)/);
      if (match) {
        console.log('[embed.js] 抽出されたAPIエンドポイントドメイン:', match[1]);
        return match[1];
      }
    }
    console.log('[embed.js] ドメイン抽出に失敗したため、window.location.originを使用します:', window.location.origin);
    return window.location.origin;
  }

  // 1. 即時実行
  scanAndEmbed();

  // 2. DOM監視
  if (typeof MutationObserver !== 'undefined') {
    console.log('[embed.js] MutationObserver によるDOM監視を開始します。');
    const observer = new MutationObserver(function() {
      scanAndEmbed();
    });
    observer.observe(document.documentElement, {
      childList: true,
      subtree: true
    });
  } else {
    console.log('[embed.js] ⚠️ このブラウザは MutationObserver に対応していません。');
  }
})();