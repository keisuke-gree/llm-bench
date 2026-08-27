<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\RankingDao;

/**
 * ランキングに関する業務ロジックを担うクラス。
 */
final class RankingLogic
{
    public function __construct(private RankingDao $rankingDao)
    {
    }

    /**
     * @return array<string,mixed>
     */
    public function fetchDetail(int $rankingId): array
    {
        return $this->rankingDao->findById($rankingId);
    }

    /**
     * @return list<array<string,mixed>>
     */
    public function listForUser(int $userId): array
    {
        $records = $this->rankingDao->findAllByUserId($userId);
        $result = [];

        foreach ($records as $record) {
            if ($record['active'] ?? true) {
                $result[] = $record;
            }
        }

        return $result;
    }

    public function process(int $userId, int $rankingId): bool
    {
        $record = $this->rankingDao->findById($rankingId);
        if ($record === []) {
            return false;
        }

        $this->rankingDao->markProcessed($userId, $rankingId);

        return true;
    }

    /**
     * ユーザー向けのランキングサマリーを組み立てる。
     */
    public function buildSummary(int $userId): array
    {
        $records = $this->rankingDao->findAllByUserId($userId);

        return ['userId' => $userId, 'total' => count($records)];
    }
}
