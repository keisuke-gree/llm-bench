<?php

declare(strict_types=1);

namespace Bench\Controller;

use Bench\Logic\CampaignResolver;
use Bench\Model\CampaignEntryModel;
use Bench\Model\UserContext;

/**
 * キャンペーン関連のHTTPリクエストを処理するコントローラー。
 */
final class CampaignController
{
    public function __construct(private CampaignResolver $campaignResolver)
    {
    }

    public function show(UserContext $context): array
    {
        $campaign = $this->campaignResolver->resolve($context);

        return ['campaign' => $campaign];
    }

    /**
     * キャンペーンエントリー情報を組み立ててレスポンスを返す。
     */
    public function entry(UserContext $context): array
    {
        if ($context->campaignId === null) {
            return ['entry' => null];
        }

        $entry = new CampaignEntryModel($context->campaignId, $context->userId);

        return ['entry' => $entry->toArray()];
    }
}
