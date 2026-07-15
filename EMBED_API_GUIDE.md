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
- APIキーはクライアント詳細画面（`/dashboard/clients/:id/api_settings`）で確認可能
- 「再発行する」ボタンから、その場でAPIキーを再発行できます（旧キーは即時に無効化されます）

### 4. ジャンル管理

- `GenreRegistry::GENRES` で定義されたジャンルから選択
- クライアントごとに異なるジャンルを割り当て可能
- 複数ジャンルの許可も可能

---

## クライアント側フロー

### 1. APIキー取得

1. 管理者からAPIキーを受け取る
2. APIキーを安全に管理（環境変数等）。チャットやメールの本文に直接貼らないよう注意してください
3. 万が一APIキーが漏洩した場合は、管理者に依頼して「再発行」を行ってください（再発行すると旧キーは即時に使えなくなります）

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

**クエリパラメータ（すべて省略可）**:

| パラメータ | 説明 | 例 |
|---|---|---|
| `genre` | ジャンル（key または日本語名）で絞り込み | `genre=cleaning` |
| `article_type` | 記事タイプで絞り込み（`pillar` / `child` / `cluster`） | `article_type=pillar` |
| `updated_since` | この日時以降に更新された記事のみ取得（ISO8601形式） | `updated_since=2026-07-01T00:00:00+09:00` |
| `page` | ページ番号（デフォルト: 1） | `page=2` |
| `per_page` | 1ページあたりの件数（デフォルト: 50、最大: 100） | `per_page=20` |

**レスポンス**:
```json
{
  "articles": [
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
      "published_at": "2026-06-18T00:00:00+09:00",
      "created_at": "2026-06-18T00:00:00+09:00",
      "updated_at": "2026-06-18T00:00:00+09:00"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 50,
    "total_count": 120,
    "total_pages": 3
  }
}
```

**注意**: 差分同期を行う場合は `updated_since` を使うと、更新された記事のみを効率的に取得できます。

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

**注意**: 記事はIDではなくcode（slug）で指定します。レスポンス形式は一覧取得の1件分（`articles`配列の中身）と同じ単一オブジェクトです。

### HTMLレンダリング

```bash
curl -X POST https://your-domain.com/api/v1/articles/render_html \
  -H "X-API-Key: YOUR_API_KEY"
```

**レスポンス**: HTML形式の記事一覧

---

## Webhook連携（オプション）

### Webhook設定

管理画面（クライアント詳細のAPI設定、またはクライアント自身の `/dashboard/api_settings`）でWebhook URLを設定すると、記事の公開・更新・非公開化のタイミングで、そのURLへHTTP POSTで自動通知が送信されます。

### 通知されるタイミング

| イベント | 発生する場面 |
|---|---|
| `created` | 記事が新しく公開された時（`published_at` が設定された時） |
| `updated` | 公開済みの記事のタイトル・本文・ジャンル・ステータス等が変更された時 |
| `deleted` | 公開済みの記事が非公開に戻された時、または記事自体が削除された時 |

### Webhookペイロード

```json
{
  "event": "created",
  "article": {
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
    "published_at": "2026-06-18T00:00:00+09:00",
    "updated_at": "2026-06-18T00:00:00+09:00"
  }
}
```

### 注意事項

- 通知は非同期のバックグラウンド処理で送信されます。相手サーバーが一時的に応答しない場合は最大3回まで再送を試みますが、それ以上のリトライは行いません（確実な取り込みが必要な場合は、`updated_since` パラメータで定期的に一覧取得APIをポーリングし、Webhookと併用することを推奨します）
- 現時点ではWebhook署名検証（送信元がこのシステムであることの検証）は未実装です。受信側でURLを推測されにくいものにするなどの対策を検討してください

---

## トラブルシューティング

### 記事が表示されない

1. APIキーが正しいか確認
2. 許可ジャンルに記事のジャンルが含まれているか確認（許可ジャンル外の記事は404にならず、単に一覧やレンダリング結果に含まれません）
3. 記事が公開済み（`published_at` が設定されている）であり、bodyが空でないことを確認
4. ブラウザコンソールでエラーを確認

### APIエラー

- `401 Unauthorized`: APIキーが無効
- `403 Forbidden`: プランでAPI機能が無効になっている（ジャンル不一致ではこのエラーは出ません）
- `404 Not Found`: 記事が存在しない、または許可ジャンル・公開範囲外
- `400 Bad Request`: `updated_since` の日時形式が不正
- `429 Too Many Requests`: リクエスト回数の制限を超えた（下記「リクエスト制限」参照）。レスポンスの `Retry-After` ヘッダーに記載された秒数待ってから再試行してください

### スタイリングが崩れる

- CSSクラスを確認してカスタマイズ
- 既存CSSとの競合を確認

---

## リクエスト制限（レート制限）

`/api/v1/*` への過剰なアクセスを防ぐため、以下の制限を設けています。

| 単位 | 制限 |
|---|---|
| APIキーごと | 1分間に60リクエストまで |
| APIキーなしのアクセス（IPアドレスごと） | 1分間に20リクエストまで |

制限を超えると `429 Too Many Requests` が返されます。定期的にデータを取得する場合は、`updated_since` パラメータを使った差分取得を利用し、全件取得を頻繁に繰り返さないようにしてください。

---

## セキュリティ

- APIキーは秘密に管理し、チャットやメール本文に直接貼らない
- 漏洩した場合は管理画面から「再発行」を行う（旧キーは即時に無効化されます）
- HTTPSを使用
- Webhook署名検証（未実装。今後の課題）

---

## サポート

不明点がある場合は管理者にお問い合わせください。
