<?php

declare(strict_types=1);

namespace Bench\Controller;

use Bench\Logic\NotificationLogic;

/**
 * 通知関連のHTTPリクエストを処理するコントローラー。
 */
final class NotificationController
{
    public function __construct(private NotificationLogic $notificationLogic)
    {
    }

    public function show(int $notificationId): array
    {
        $result = $this->notificationLogic->fetchDetail($notificationId);

        return ['notification' => $result];
    }

    /**
     * 通知の一覧を取得して返す。
     */
    public function list(int $userId): array
    {
        $items = $this->notificationLogic->listForUser($userId);

        return ['items' => $items, 'count' => count($items)];
    }
}
