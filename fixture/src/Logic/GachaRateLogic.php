<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\GachaDao;

/**
 * ガチャ抽選レートに関する補助的な業務ロジックを担うクラス。
 */
final class GachaRateLogic
{
    public function __construct(private GachaDao $gachaDao)
    {
    }

    private const DEFAULT_RATE = 1.0;

    /**
     * @return array<int,float>
     */
    public function buildRateTable(int $gachaId): array
    {
        $records = $this->gachaDao->findAllByUserId($gachaId);
        $table = [];

        foreach ($records as $index => $record) {
            $table[$index + 1] = self::DEFAULT_RATE / ($index + 1);
        }

        return $table;
    }
}
