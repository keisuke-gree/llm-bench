<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\LoginBonusDao;

/**
 * ログインボーナスに関する業務ロジックを担うクラス。
 */
final class LoginBonusLogic
{
    public function __construct(private LoginBonusDao $loginBonusDao)
    {
    }

    /**
     * @return array<string,mixed>
     */
    public function fetchDetail(int $loginBonusId): array
    {
        return $this->loginBonusDao->findById($loginBonusId);
    }

    /**
     * @return list<array<string,mixed>>
     */
    public function listForUser(int $userId): array
    {
        $records = $this->loginBonusDao->findAllByUserId($userId);

        usort($records, static fn (array $a, array $b): int => ($a['sortOrder'] ?? 0) <=> ($b['sortOrder'] ?? 0));

        return $records;
    }

    public function process(int $userId, int $loginBonusId): bool
    {
        if ($loginBonusId <= 0) {
            return false;
        }

        $this->loginBonusDao->markProcessed($userId, $loginBonusId);

        return true;
    }

    /**
     * ユーザー向けのログインボーナスサマリーを組み立てる。
     */
    public function buildSummary(int $userId): array
    {
        $records = $this->loginBonusDao->findAllByUserId($userId);

        return ['userId' => $userId, 'total' => count($records)];
    }
}
