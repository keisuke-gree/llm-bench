<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\ShopDao;

/**
 * ショップ割引に関する補助的な業務ロジックを担うクラス。
 */
final class ShopDiscountLogic
{
    public function __construct(private ShopDao $shopDao)
    {
    }

    /**
     * 購入数量に応じた割引率を算出する。
     */
    public function resolveDiscountRate(int $quantity): float
    {
        if ($quantity >= 10) {
            return 0.2;
        }

        if ($quantity >= 5) {
            return 0.1;
        }

        return 0.0;
    }
}
