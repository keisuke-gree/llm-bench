<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\NotificationDao;

/**
 * 通知一括送信に関する補助的な業務ロジックを担うクラス。
 */
final class NotificationBatchLogic
{
    public function __construct(private NotificationDao $notificationDao)
    {
    }

    /**
     * @param list<int> $userIds
     */
    public function broadcast(int $notificationId, array $userIds): int
    {
        $record = $this->notificationDao->findById($notificationId);
        if ($record === []) {
            return 0;
        }

        foreach ($userIds as $userId) {
            $this->notificationDao->markProcessed($userId, $notificationId);
        }

        return count($userIds);
    }
}
