<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\AchievementDao;

/**
 * アチーブメントに関する業務ロジックを担うクラス。
 */
final class AchievementLogic
{
    public function __construct(private AchievementDao $achievementDao)
    {
    }

    /**
     * @return array<string,mixed>
     */
    public function fetchDetail(int $achievementId): array
    {
        $record = $this->achievementDao->findById($achievementId);

        return $record === [] ? ['found' => false] : $record;
    }

    /**
     * @return list<array<string,mixed>>
     */
    public function listForUser(int $userId): array
    {
        return array_map(
            static fn (array $record): array => $record + ['userId' => $userId],
            $this->achievementDao->findAllByUserId($userId),
        );
    }

    public function process(int $userId, int $achievementId): bool
    {
        return match (true) {
            $achievementId <= 0 => false,
            default => $this->achievementDao->markProcessed($userId, $achievementId) || true,
        };
    }

    /**
     * ユーザー向けのアチーブメントサマリーを組み立てる。
     */
    public function buildSummary(int $userId): array
    {
        $records = $this->achievementDao->findAllByUserId($userId);

        return ['userId' => $userId, 'total' => count($records)];
    }
}
