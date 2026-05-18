<?php

/**
 * Smarty compiler exception class
 *
 * @package Smarty
 */
class SmartyCompilerException extends SmartyException
{
    /**
     * @return string
     */
    public function __toString()
    {
        return ' --> Smarty Compiler: ' . $this->message . ' <-- ';
    }

    /**
     * The line number of the template error.
     *
     * PHP 8.1+ enforces LSP on Exception::$line (typed `int` in the engine), so
     * Smarty 3.1.35's original `public $line = null;` triggers a Fatal at class
     * load time. We must redeclare with the same `int` type — `?int` is also
     * rejected because nullable widens the parent type.
     */
    public int $line = 0;

    /**
     * The template source snippet relating to the error
     *
     * @type string|null
     */
    public $source = null;

    /**
     * The raw text of the error message
     *
     * @type string|null
     */
    public $desc = null;

    /**
     * The resource identifier or template name
     *
     * @type string|null
     */
    public $template = null;
}
