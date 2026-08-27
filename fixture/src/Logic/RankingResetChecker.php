<?php

declare(strict_types=1);

namespace Bench\Logic;

/**
 * ランキング集計期間のリセット判定を行うクラス。
 */
final class RankingResetChecker
{
    private const RESET_INTERVAL_DAYS = 7;

    /**
     * 前回リセット日時から、次のリセットタイミングを過ぎているかを判定する。
     */
    public function shouldReset(\DateTimeImmutable $lastResetAt, \DateTimeImmutable $now): bool
    {
        // TODO: 週次リセットではなく月初リセットに変更したいという要望があるため、
        //       対応方針を別途検討する。
        $nextResetAt = $lastResetAt->modify('+' . self::RESET_INTERVAL_DAYS . ' days');

        return $now >= $nextResetAt;
    }
}
