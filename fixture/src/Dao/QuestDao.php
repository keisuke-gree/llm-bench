<?php

declare(strict_types=1);

namespace Bench\Dao;

/**
 * クエストの進行状況・定義情報を取得するデータアクセスクラス。
 */
final class QuestDao
{
    /**
     * @return array{rank:int,clearCount:int}
     */
    public function findById(int $questId): array
    {
        $table = [
            1 => ['rank' => 1, 'clearCount' => 0],
            2 => ['rank' => 2, 'clearCount' => 3],
            3 => ['rank' => 5, 'clearCount' => 12],
        ];

        return $table[$questId] ?? ['rank' => 1, 'clearCount' => 0];
    }

    public function incrementClearCount(int $questId): void
    {
        // クリア回数の永続化はストレージ層に委譲する想定
    }

    /**
     * @return list<int>
     */
    public function findUnlockedQuestIds(int $userLevel): array
    {
        $unlocked = [];
        $thresholds = [1 => 1, 2 => 5, 3 => 10, 4 => 20];

        foreach ($thresholds as $questId => $requiredLevel) {
            if ($userLevel >= $requiredLevel) {
                $unlocked[] = $questId;
            }
        }

        return $unlocked;
    }
}
