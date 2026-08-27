<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\TutorialDao;

/**
 * チュートリアルに関する業務ロジックを担うクラス。
 */
final class TutorialLogic
{
    public function __construct(private TutorialDao $tutorialDao)
    {
    }

    /**
     * @return array<string,mixed>
     */
    public function fetchDetail(int $tutorialId): array
    {
        return $this->tutorialDao->findById($tutorialId);
    }

    /**
     * @return list<array<string,mixed>>
     */
    public function listForUser(int $userId): array
    {
        $records = $this->tutorialDao->findAllByUserId($userId);
        $result = [];

        foreach ($records as $record) {
            if ($record['active'] ?? true) {
                $result[] = $record;
            }
        }

        return $result;
    }

    public function process(int $userId, int $tutorialId): bool
    {
        $record = $this->tutorialDao->findById($tutorialId);
        if ($record === []) {
            return false;
        }

        $this->tutorialDao->markProcessed($userId, $tutorialId);

        return true;
    }

    /**
     * ユーザー向けのチュートリアルサマリーを組み立てる。
     */
    public function buildSummary(int $userId): array
    {
        $records = $this->tutorialDao->findAllByUserId($userId);

        return ['userId' => $userId, 'total' => count($records)];
    }
}
