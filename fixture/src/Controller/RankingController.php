<?php

declare(strict_types=1);

namespace Bench\Controller;

use Bench\Logic\RankingLogic;

/**
 * ランキング関連のHTTPリクエストを処理するコントローラー。
 */
final class RankingController
{
    public function __construct(private RankingLogic $rankingLogic)
    {
    }

    /**
     * ランキングに関する操作結果を返す。
     */
    public function execute(int $userId, int $rankingId): array
    {
        $succeeded = $this->rankingLogic->process($userId, $rankingId);

        return ['succeeded' => $succeeded];
    }

    public function summary(int $userId): array
    {
        return $this->rankingLogic->buildSummary($userId);
    }
}
