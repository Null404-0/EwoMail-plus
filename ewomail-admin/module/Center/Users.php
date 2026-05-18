<?php
// +----------------------------------------------------------------------
// | EwoMail
// +----------------------------------------------------------------------
// | Copyright (c) 2016 http://ewomail.com All rights reserved.
// +----------------------------------------------------------------------
// | Licensed ( http://ewomail.com/license.html)
// +----------------------------------------------------------------------
// | Author: Jun <gyxuehu@163.com>
// +----------------------------------------------------------------------
/**
 * 邮件用户
 */
if(!defined("PATH")) exit;

//邮件列表
Rout::get('index',function(){
    Admin::setMenu(101);
    $sort = iget('sort');
    $active = iget('active');
    $email = iget('email');
    $domain = iget('domain');
    
    $where = '1';
    $order = 'a.ctime desc';
    
    if($sort){
        $sortArr = explode(':',$sort);
        $s_a = $sortArr[0];
        $s_b = $sortArr[1];
        if($s_a=='gb'){
            $order = "c.bytes $s_b";
        }
    }
    
    if($active!==''){
        $active = intval($active);
        $where .= " and a.active=$active";
    }
    
    if($email){
        $where .= " and a.email='$email'";
    }
    
    if($domain){
        $where .= " and b.name='$domain'";
    }
    
    
    
    $count = App::$db->count("select count(a.id) from ".table("users")." as a 
        left join ".table("domains")." as b on a.domain_id=b.id 
        left join ".table("quota")." as c on a.email=c.email 
        where $where");
    $page = new Page($count,20);
    $list = App::$db->select("select a.*,c.bytes from ".table("users")." as a 
        left join ".table("domains")." as b on a.domain_id=b.id 
        left join ".table("quota")." as c on a.email=c.email 
        where $where order by $order {$page->limit}");
    $arr = [
        'list'=>$list,
        'page'=>$page->show()
    ];

    Tp::assign($arr);
    Tp::display();
});

//邮件删除
Rout::delete('index',function(){
    Admin::setMenu(101);
    $id = iany('id');
    $users = new User();
    if(is_array($id)){
        $del_file = PATH."/cache/delete.txt";
        if(!file_exists($del_file)){
            E::error(L(1213).$del_file);
        }
        foreach($id as $v)
        {
            $users->delete(intval($v));
        }
    }else{
        $users->delete(intval($id));
    }
    
    E::success(1003);
});


//邮件编辑页面
Rout::get('edit',function(){
    $id = intval(iget('id'));
    $title = $gid?L(2001).L(1103):'';
    Admin::setMenu(102,$title);

    if($id){
        $users = new User();
        $row = $users->getOne($id);
    }

    // 批量添加要用：列出所有域名（按名称排序）。
    $domains = App::$db->select("select id,name,active from " . table("domains") . " order by name asc");
    if (!$domains) $domains = [];

    Tp::assign([
        'row'     => $row,
        'domains' => $domains,
    ]);
    Tp::display();
});

//邮件编辑数据保存
Rout::put('edit',function(){
    Admin::setMenu(101);
    $id = intval(iget('id'));
    $users = new User();
    $users->save([],$id);
    E::success(1001);
});


//邮件系统设置
Rout::get('config',function(){
    Admin::setMenu(105);
    $mailConfig = new MailConfig();
    $row = $mailConfig->getAll();
    $arr = [
        'row'=>$row
    ];
    Tp::assign($arr);
    Tp::display();
});

Rout::put('config',function(){
    Admin::setMenu(105);
    $data = ipost('data');
    $type = ipost('type');
    $mailConfig = new MailConfig();
    $mailConfig->save($data);
    if($type=='senior'){
        $sendData = [
            'myhostname'=>$data['myhostname'],
            'mydomain'=>$data['mydomain']
        ];
        $server = new Server();
        $server->send("root","update_mail_config",$sendData);
        $logData = [
            'ac'=>'edit',
            'c'=>'邮件系统设置'
        ];
        AdminLog::save($logData);
    }
    E::success(1001);
});

//收发数量页面
Rout::get('rec',function(){
    Admin::setMenu(101);
    $id = intval(iget('id'));
    $start_day = iget('start_day');
    $end_day = iget('end_day');
    
    $users = new User();
    $row = $users->getOne($id);
    
    $date = new Date();
    $d = $date->format("%Y-%m-%d");
    $where = "email='$row[email]'";
    
    if($start_day){
        $where .= " and day>='$start_day'";
    }
    
    if($end_day){
        $where .= " and day<='$end_day'";
    }
    
    $count = App::$db->count("select count(day_id) from ".table("day_record")." where $where");
    $page = new Page($count,10);
    $list = App::$db->select("select * from ".table("day_record")." where $where order by day desc {$page->limit}");
    $arr = [
        'list'=>$list,
        'page'=>$page->show()
    ];
    
    Tp::assign($arr);
    Tp::display();
});


//收发数量页面
Rout::put('rec',function(){
    Admin::setMenu(101);
    $day_id = intval(iget('day_id'));
    $clean = iget('clean');
    $row = App::$db->getOne("select * from ".table("day_record")." where day_id=$day_id");
    if(!$row) E::error(1005);
    if($clean=='s'){
        $newData = [
            's_num'=>0
        ];
        App::$db->update("day_record",$newData,"day_id=$day_id");
    }else if($clean=='c'){
        $newData = [
            'c_num'=>0
        ];
        App::$db->update("day_record",$newData,"day_id=$day_id");
    }else{
        E::error(1002);
    }
    E::success(1001);

});

/**
 * 批量添加邮箱。在 /Users/edit 页面（添加模式）下方提供。
 * 用户指定: 字母数 / 数字数 / 是否打乱 / 数量 / 密码模式。
 * 返回每个账号的 email + plaintext password（一次性显示供用户下载），
 * 数据库里只存 md5 哈希（和单个添加保持一致）。
 */
Rout::put('batch-add', function () {
    Admin::setMenu(102);
    $domain     = trim(ipost('domain'));
    $quantity   = intval(ipost('quantity'));
    $letters    = intval(ipost('letters'));
    $digits     = intval(ipost('digits'));
    $mixed      = ipost('mixed') === '1';
    $pwd_mode   = ipost('pwd_mode');       // 'shared' | 'random'
    $shared_pwd = trim(ipost('password')); // 仅当 pwd_mode=shared

    if ($quantity < 1 || $quantity > 500) {
        E::error('数量需在 1-500 之间（一次太多容易超出 maildir 创建配额）');
    }
    if ($letters < 0 || $letters > 32 || $digits < 0 || $digits > 32) {
        E::error('字母数 / 数字数需在 0-32 之间');
    }
    $total_len = $letters + $digits;
    if ($total_len < 3) E::error('用户名长度不能少于 3 字符');
    if ($total_len > 32) E::error('用户名长度不能超过 32 字符');
    // 字符空间够不够：总位数太小 + 数量太大 → 必然重复，提前拦
    // 23 (letters_pool) ^L * 8 (digits_pool) ^D 的对数估算，避免浮点溢出
    $log_space = $letters * 4.5 + $digits * 3;  // log2(23)≈4.52, log2(8)=3
    if ($log_space < log($quantity * 50, 2)) {
        E::error('随机空间不够（' . $quantity . ' 个账号需要更长的用户名），请增加字母或数字位数');
    }

    $domainRow = App::$db->getOne(
        "select * from " . table("domains") . " where name='" . addslashes($domain) . "'"
    );
    if (!$domainRow) E::error('该域名不存在，请先在「邮件域名」里添加');

    if ($pwd_mode === 'shared') {
        if (strlen($shared_pwd) < 8 || strlen($shared_pwd) > 64) {
            E::error('统一密码长度需在 8-64 字符之间');
        }
    } else if ($pwd_mode !== 'random') {
        E::error('密码模式无效');
    }

    // 字符池（去掉容易看错的字符 0/O/1/l/I）
    $letter_pool = 'abcdefghjkmnpqrstuvwxyz';   // 23 个
    $digit_pool  = '23456789';                  // 8 个
    $pwd_pool    = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789!@#%&*+-_=';

    $gen_name = function () use ($letters, $digits, $mixed, $letter_pool, $digit_pool) {
        $part_l = '';
        for ($i = 0; $i < $letters; $i++) $part_l .= $letter_pool[random_int(0, strlen($letter_pool) - 1)];
        $part_d = '';
        for ($i = 0; $i < $digits;  $i++) $part_d .= $digit_pool[random_int(0, strlen($digit_pool) - 1)];
        $s = $part_l . $part_d;
        if ($mixed && strlen($s) > 1) {
            // PHP 自带 str_shuffle 用的是 rand()，安全性较弱；做一个基于 random_int 的 Fisher-Yates
            $arr = str_split($s);
            for ($i = count($arr) - 1; $i > 0; $i--) {
                $j = random_int(0, $i);
                $tmp = $arr[$i]; $arr[$i] = $arr[$j]; $arr[$j] = $tmp;
            }
            $s = implode('', $arr);
        }
        return $s;
    };
    $gen_pwd = function () use ($pwd_pool) {
        $s = '';
        for ($i = 0; $i < 16; $i++) $s .= $pwd_pool[random_int(0, strlen($pwd_pool) - 1)];
        return $s;
    };

    $created  = [];
    $local_seen = [];   // 本批次内防重
    $tries    = 0;
    $max_tries = max($quantity * 10, 100);
    $user_obj = new User();

    while (count($created) < $quantity && $tries < $max_tries) {
        $tries++;
        $name  = $gen_name();
        $email = strtolower($name . '@' . $domain);
        if (isset($local_seen[$email])) continue;

        $exists = App::$db->count(
            "select count(id) from " . table("users") . " where email='" . addslashes($email) . "'"
        );
        if ($exists) continue;

        $pwd = ($pwd_mode === 'shared') ? $shared_pwd : $gen_pwd();

        App::$db->insert('users', [
            'email'     => $email,
            'active'    => 1,
            'domain_id' => $domainRow['id'],
            'password'  => md5($pwd),
            'limits'    => 1,
            'limitg'    => 1,
            'uname'     => '',
            'tel'       => '',
            'maildir'   => $user_obj->createMailDir($name, $domain),
            'ctime'     => App::$format,
        ]);
        $created[]      = ['email' => $email, 'password' => $pwd];
        $local_seen[$email] = true;
    }

    AdminLog::save(['ac' => 'add', 'c' => '批量创建邮箱：' . count($created) . ' 个 @' . $domain]);

    $note = '';
    if (count($created) < $quantity) {
        $note = '（'. (count($created)) .'/'. $quantity .'：剩余因随机冲突或与现有邮箱重名跳过）';
    }
    E::success('已生成 ' . count($created) . ' 个账号' . $note, '', $created);
});