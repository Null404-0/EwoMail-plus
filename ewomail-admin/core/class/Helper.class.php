<?php
/**
 * Helper: thin wrapper around /ewomail/sbin/ewomail-helper, invoked via sudo.
 * Every call performs strict argument validation locally before shelling out;
 * the helper script revalidates server-side as defence in depth.
 */
if (!defined('PATH')) exit;

class Helper
{
    const HELPER = '/ewomail/sbin/ewomail-helper';

    /**
     * Run helper subcommand. Returns ['ok'=>bool,'out'=>string,'rc'=>int].
     * $args MUST already be validated by the caller.
     */
    public static function run(array $args, $stdin = null)
    {
        $cmd = 'sudo -n ' . escapeshellarg(self::HELPER);
        foreach ($args as $a) {
            $cmd .= ' ' . escapeshellarg($a);
        }
        $cmd .= ' 2>&1';

        if ($stdin === null) {
            $out = [];
            $rc  = 0;
            exec($cmd, $out, $rc);
            return ['ok' => $rc === 0, 'out' => implode("\n", $out), 'rc' => $rc];
        }

        // Pipe stdin in.
        $proc = proc_open($cmd, [
            0 => ['pipe', 'r'],
            1 => ['pipe', 'w'],
            2 => ['pipe', 'w'],
        ], $pipes);
        if (!is_resource($proc)) {
            return ['ok' => false, 'out' => 'proc_open failed', 'rc' => -1];
        }
        fwrite($pipes[0], $stdin);
        fclose($pipes[0]);
        $out = stream_get_contents($pipes[1]) . stream_get_contents($pipes[2]);
        fclose($pipes[1]); fclose($pipes[2]);
        $rc = proc_close($proc);
        return ['ok' => $rc === 0, 'out' => $out, 'rc' => $rc];
    }

    public static function validatePortProto($s)
    {
        return (bool)preg_match('#^[0-9]{1,5}/(tcp|udp)$#', $s);
    }
    public static function validateIPv4($s)
    {
        return filter_var($s, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) !== false;
    }
    public static function validateFqdn($s)
    {
        return (bool)preg_match('/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/i', $s);
    }
    public static function validateSiteName($s)
    {
        return (bool)preg_match('/^[A-Za-z0-9._-]+\.conf$/', $s);
    }

    /** Reads a panel setting from i_panel_setting (created by installer). */
    public static function setting($name, $default = '')
    {
        // Whitelist: panel keys are fixed, so we never accept arbitrary input.
        static $allowed = [
            'admin_path', 'db_path', 'db_admin_enable',
            'mail_host', 'public_ip', 'le_email',
        ];
        if (!in_array($name, $allowed, true)) {
            return $default;
        }
        $row = App::$db->getOne("SELECT value FROM i_panel_setting WHERE name='" . $name . "'");
        return isset($row['value']) ? $row['value'] : $default;
    }
}
