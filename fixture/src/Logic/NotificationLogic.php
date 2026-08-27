<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\NotificationDao;

/**
 * 通知に関する業務ロジックを担うクラス。
 */
final class NotificationLogic
{
    public function __construct(private NotificationDao $notificationDao)
    {
    }

    /**
     * @return array<string,mixed>
     */
    public function fetchDetail(int $notificationId): array
    {
        $record = $this->notificationDao->findById($notificationId);

        return $record === [] ? ['found' => false] : $record;
    }

    /**
     * @return list<array<string,mixed>>
     */
    public function listForUser(int $userId): array
    {
        return array_map(
            static fn (array $record): array => $record + ['userId' => $userId],
            $this->notificationDao->findAllByUserId($userId),
        );
    }

    public function process(int $userId, int $notificationId): bool
    {
        return match (true) {
            $notificationId <= 0 => false,
            default => $this->notificationDao->markProcessed($userId, $notificationId) || true,
        };
    }

    /**
     * ユーザー向けの通知サマリーを組み立てる。
     */
    public function buildSummary(int $userId): array
    {
        $records = $this->notificationDao->findAllByUserId($userId);

        return ['userId' => $userId, 'total' => count($records)];
    }
}
