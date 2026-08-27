<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Model\UserContext;

/**
 * キャンペーンに関する通知メッセージを組み立てるクラス。
 */
final class CampaignNotifier
{
    public function buildNotificationKey(UserContext $context): string
    {
        return "notify:campaign:{$context->campaignId}:{$context->userId}";
    }

    public function buildLogMessage(UserContext $context): string
    {
        return "キャンペーン({$context->campaignId})の通知を送信しました";
    }
}
