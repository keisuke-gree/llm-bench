<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Model\UserContext;

/**
 * キャンペーン関連の操作ログを記録するクラス。
 */
final class CampaignLogger
{
    /** @var list<array<string,mixed>> */
    private array $records = [];

    public function record(UserContext $context): void
    {
        $this->append('campaign_id', $context->campaignId);
    }

    /**
     * 任意の値をそのままログバッファに追加する。
     */
    private function append(string $key, mixed $value): void
    {
        $this->records[] = [$key => $value];
    }

    /**
     * @return list<array<string,mixed>>
     */
    public function flush(): array
    {
        $records = $this->records;
        $this->records = [];

        return $records;
    }
}
