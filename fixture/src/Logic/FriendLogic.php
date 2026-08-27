<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\FriendDao;

/**
 * フレンドに関する業務ロジックを担うクラス。
 */
final class FriendLogic
{
    public function __construct(private FriendDao $friendDao)
    {
    }

    /**
     * @return array<string,mixed>
     */
    public function fetchDetail(int $friendId): array
    {
        return $this->friendDao->findById($friendId);
    }

    /**
     * @return list<array<string,mixed>>
     */
    public function listForUser(int $userId): array
    {
        $records = $this->friendDao->findAllByUserId($userId);

        usort($records, static fn (array $a, array $b): int => ($a['sortOrder'] ?? 0) <=> ($b['sortOrder'] ?? 0));

        return $records;
    }

    public function process(int $userId, int $friendId): bool
    {
        if ($friendId <= 0) {
            return false;
        }

        $this->friendDao->markProcessed($userId, $friendId);

        return true;
    }

    /**
     * ユーザー向けのフレンドサマリーを組み立てる。
     */
    public function buildSummary(int $userId): array
    {
        $records = $this->friendDao->findAllByUserId($userId);

        return ['userId' => $userId, 'total' => count($records)];
    }
}
