<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\FriendDao;

/**
 * フレンドポイントに関する補助的な業務ロジックを担うクラス。
 */
final class FriendPointLogic
{
    public function __construct(private FriendDao $friendDao)
    {
    }

    /**
     * フレンド申請承認時に付与するポイントを算出する。
     */
    public function resolveGrantPoint(int $friendCount): int
    {
        return min(100, $friendCount * 5);
    }
}
