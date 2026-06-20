# 埋め込みAPIシステム UXフロー

## 概要

このシステムはAI生成記事を他サイトに配信するための埋め込みAPIシステムです。クライアントはAPIキーを使用して記事を取得し、自サイトに埋め込むことができます。

---

## 管理者側フロー

### 1. クライアント登録

1. 管理画面にログイン
2. `/dashboard/management` にアクセス
3. 「新規クライアント登録」ボタンをクリック
4. 以下の情報を入力:
   - メールアドレス
   - 会社名
   - ドメイン
   - 連絡先情報

### 2. API設定

1. クライアント詳細画面にアクセス
2. 「API設定」セクションで以下を設定:
   - **許可ジャンル**: クライアントがアクセス可能なジャンルを選択
     - 例: `["cleaning", "cargo"]`
   - **Webhook URL**: 記事更新時の通知先URL（オプション）
     - 例: `https://client-site.com/webhook/articles`
   - **埋め込み設定**: カスタマイズ設定（オプション）

### 3. APIキー発行

- クライアント登録時に自動的にAPIキーが発行されます
- APIキーはクライアント詳細画面で確認可能
- 必要に応じて再発行可能

### 4. ジャンル管理

- `GenreRegistry::GENRES` で定義されたジャンルから選択
- クライアントごとに異なるジャンルを割り当て可能
- 複数ジャンルの許可も可能

---

## クライアント側フロー

### 1. APIキー取得

1. 管理者からAPIキーを受け取る
2. APIキーを安全に管理（環境変数等）

### 2. 埋め込みタグ設置

#### 基本的な設置方法

**ステップ1: 記事を表示する場所にコンテナを追加**

```html
<!-- サイトの任意の場所（例: メインコンテンツエリア） -->
<div id="articles"></div>
```

**ステップ2: ページの最後にスクリプトタグを追加**

```html
<!-- </body>タグの直前に追加 -->
<script src="https://your-domain.com/embed.js" data-api-key="YOUR_API_KEY"></script>
```

**完全なHTML例**:
```html
<!DOCTYPE html>
<html>
<head>
  <title>私のサイト</title>
</head>
<body>
  <h1>最新記事</h1>
  
  <!-- ここに記事が表示されます -->
  <div id="articles"></div>
  
  <!-- ページの最後にスクリプトを追加 -->
  <script src="https://your-domain.com/embed.js" data-api-key="YOUR_API_KEY"></script>
</body>
</html>
```

#### カスタマイズ方法

**カスタムコンテナIDを使用する場合**:

```html
<!-- カスタムコンテナIDを指定 -->
<div id="my-articles"></div>

<script 
  src="https://your-domain.com/embed.js" 
  data-api-key="YOUR_API_KEY"
  data-container-id="my-articles">
</script>
```

### 3. 表示される内容

スクリプトが読み込まれると、以下の内容が自動的に表示されます：

- **記事タイトル**: 各記事の見出し
- **記事本文**: 記事の内容
- **記事画像**: 画像がある場合
- **メタ情報**: ジャンル、キーワード、更新日時など

**表示される場所**: `<div id="articles">`（または指定したコンテナID）の中に記事が自動的に挿入されます。

### 4. 表示確認

1. サイトにアクセス
2. 記事が自動的に読み込まれることを確認
3. ブラウザの開発者ツールで `<div id="articles">` の中に記事が挿入されているか確認
4. スタイリングをカスタマイズ（必要な場合）

### 4. スタイリング

埋め込み記事には以下のCSSクラスが付与されます:

```css
.embedded-article {
  /* 記事コンテナ */
}

.article-title {
  /* 記事タイトル */
}

.article-body {
  /* 記事本文 */
}

.article-meta {
  /* メタデータ（ジャンル、日付等） */
}

.embed-loading {
  /* ローディング中表示 */
}

.embed-error {
  /* エラー表示 */
}
```

---

## APIエンドポイント

### 記事一覧取得

```bash
curl -X GET https://your-domain.com/api/v1/articles \
  -H "X-API-Key: YOUR_API_KEY"
```

**レスポンス**:
```json
[
  {
    "id": 1,
    "title": "記事タイトル",
    "body": "記事本文",
    "description": "記事説明",
    "genre": "cleaning",
    "sub_genre": null,
    "code": "article-slug",
    "keyword": "キーワード",
    "status": "approved",
    "article_type": "cluster",
    "file_url": "https://...",
    "created_at": "2026-06-18T00:00:00+09:00",
    "updated_at": "2026-06-18T00:00:00+09:00",
    "url": "https://your-domain.com/api/v1/articles/article-slug"
  }
]
```

**注意**: 各記事には `url` フィールドが含まれており、これを使用して個別の記事詳細にアクセスできます。

### 単一記事取得

```bash
curl -X GET https://your-domain.com/api/v1/articles/:code \
  -H "X-API-Key: YOUR_API_KEY"
```

**例**:
```bash
curl -X GET https://your-domain.com/api/v1/articles/article-slug \
  -H "X-API-Key: YOUR_API_KEY"
```

**注意**: 記事はIDではなくcode（slug）で指定します。

### HTMLレンダリング

```bash
curl -X POST https://your-domain.com/api/v1/articles/render_html \
  -H "X-API-Key: YOUR_API_KEY"
```

**レスポンス**: HTML形式の記事一覧

---

## Webhook連携（オプション）

### Webhook設定

管理者がクライアントのWebhook URLを設定すると、記事更新時に自動通知が送信されます。

### Webhookペイロード

```json
{
  "event": "created",
  "article": {
    "id": 1,
    "title": "記事タイトル",
    "body": "記事本文",
    "genre": "cleaning",
    "updated_at": "2026-06-18T00:00:00+09:00"
  }
}
```

### イベントタイプ

- `created`: 記事作成時
- `updated`: 記事更新時
- `deleted`: 記事削除時

---

## トラブルシューティング

### 記事が表示されない

1. APIキーが正しいか確認
2. 許可ジャンルに記事のジャンルが含まれているか確認
3. 記事ステータスが `approved` であり、bodyが空でないことを確認
4. ブラウザコンソールでエラーを確認

### APIエラー

- `401 Unauthorized`: APIキーが無効
- `403 Forbidden`: ジャンル許可なし
- `404 Not Found`: 記事が存在しない

### スタイリングが崩れる

- CSSクラスを確認してカスタマイズ
- 既存CSSとの競合を確認

---

## セキュリティ

- APIキーは秘密に管理
- HTTPSを使用
- Webhook署名検証（将来実装予定）
- レート制限（将来実装予定）

---

## サポート

不明点がある場合は管理者にお問い合わせください。
