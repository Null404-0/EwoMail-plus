<?php

class UnicodePlugin extends \RainLoop\Plugins\AbstractPlugin
{
    const CFG_FILE = __DIR__ . '/config.json';

    public function Init()
    {
        $this->addCss('assets/unicode.css');
        $this->addJs('assets/unicode.js');
    }

    public function configData()
    {
        $cfg = [
            'turnstile_enabled' => '0',
            'turnstile_site_key' => '',
            'turnstile_secret_key' => '',
            'outbound_disabled' => 'no'
        ];
        if (is_readable(self::CFG_FILE)) {
            $raw = json_decode((string)file_get_contents(self::CFG_FILE), true);
            if (is_array($raw)) {
                $cfg = array_merge($cfg, $raw);
            }
        }
        return $cfg;
    }
}

return new UnicodePlugin();
