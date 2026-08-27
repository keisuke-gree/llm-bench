<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\QuestDao;

/**
 * クエスト進捗に関する補助的な業務ロジックを担うクラス。
 */
final class QuestProgressLogic
{
    public function __construct(private QuestDao $questDao)
    {
    }

    /**
     * @param list<int> $unlockedQuestIds
     */
    public function resolveNextQuestId(array $unlockedQuestIds, int $currentQuestId): ?int
    {
        $sorted = $unlockedQuestIds;
        sort($sorted);

        foreach ($sorted as $candidate) {
            if ($candidate > $currentQuestId) {
                return $candidate;
            }
        }

        return null;
    }
}
