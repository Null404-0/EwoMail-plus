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

    /**
     * Stream helper stdout directly to the browser. Intended for downloads.
     * Stderr is captured and returned so binary stdout is never polluted.
     */
    public static function stream(array $args, &$err = '')
    {
        $cmd = 'sudo -n ' . escapeshellarg(self::HELPER);
        foreach ($args as $a) {
            $cmd .= ' ' . escapeshellarg($a);
        }

        $proc = proc_open($cmd, [
            0 => ['pipe', 'r'],
            1 => ['pipe', 'w'],
            2 => ['pipe', 'w'],
        ], $pipes);
        if (!is_resource($proc)) {
            $err = 'proc_open failed';
            return -1;
        }
        fclose($pipes[0]);
        while (!feof($pipes[1])) {
            echo fread($pipes[1], 8192);
            if (function_exists('flush')) flush();
        }
        fclose($pipes[1]);
        $err = stream_get_contents($pipes[2]);
        fclose($pipes[2]);
        return proc_close($proc);
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
        if (!in_array($name, self::settingAllowed(), true)) {
            return $default;
        }
        $row = App::$db->getOne("SELECT value FROM i_panel_setting WHERE name='" . $name . "'");
        return isset($row['value']) ? $row['value'] : $default;
    }

    /**
     * Writes a panel setting. Same whitelist as read; values are escaped via
     * PDO::quote. Returns true/false.
     */
    public static function settingSet($name, $value)
    {
        if (!in_array($name, self::settingAllowed(), true)) {
            return false;
        }
        if (strlen($value) > 65536) {
            return false;
        }
        // $name 已经被上面的白名单约束，可以直接拼；$value 走 PDO::quote 转义。
        $sql = "REPLACE INTO i_panel_setting (name, value) VALUES ('" . $name . "', " . App::$db->quote($value) . ")";
        return App::$db->execute($sql) !== false;
    }

    /** Single source of truth for which setting keys are permitted. */
    private static function settingAllowed()
    {
        return [
            'admin_path', 'db_path', 'db_admin_enable',
            'mail_host', 'public_ip', 'le_email',
            'outbound_disabled',  // set by helper, may be read by panel
            'fw_port_descs',      // JSON: per-port custom description overrides
        ];
    }
}
