<?php

declare(strict_types=1);

namespace Bench\Controller;

use Bench\Logic\FriendLogic;

/**
 * フレンド関連のHTTPリクエストを処理するコントローラー。
 */
final class FriendController
{
    public function __construct(private FriendLogic $friendLogic)
    {
    }

    public function show(int $friendId): array
    {
        $result = $this->friendLogic->fetchDetail($friendId);

        return ['friend' => $result];
    }

    /**
     * フレンドの一覧を取得して返す。
     */
    public function list(int $userId): array
    {
        $items = $this->friendLogic->listForUser($userId);

        return ['items' => $items, 'count' => count($items)];
    }
}
