// SPDX-License-Identifier: Zlib
//
// LiteLua - data files in a subset of Lua syntax (D38). The same grammar and
// limits as tools/lsong.py (parse_lua); see ll_data.h.
//
// The parser runs inside lua_pcall: its own errors and out-of-memory errors
// of the Lua API both end up as a message, and nothing is left on the stack.

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "lauxlib.h"

#include "ll_data.h"

typedef struct {
    const char *s, *end;
    int line;
    const char *name;
    const LLDataLimits *lim;
    lua_State *L;
} Parser;

// Raises a Lua error "<name>:<line>: <message>"; caught by ll_data_parse
static void fail(Parser *p, const char *fmt, ...) __attribute__((format(printf, 2, 3), noreturn));
static void fail(Parser *p, const char *fmt, ...)
{
    char msg[128];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msg, sizeof(msg), fmt, ap);
    va_end(ap);
    lua_pushfstring(p->L, "%s:%d: %s", p->name, p->line, msg);
    lua_error(p->L);
    __builtin_unreachable();
}

static bool is_name_start(int c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

static bool is_digit(int c)
{
    return c >= '0' && c <= '9';
}

static bool is_name_char(int c)
{
    return is_name_start(c) || is_digit(c);
}

static bool is_space(int c)
{
    return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f' || c == '\v';
}

static int hex_value(int c)
{
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}

// At '[': the level of a long bracket [[ or [==[, or -1
static int long_bracket(const Parser *p)
{
    const char *q = p->s + 1;
    int level = 0;
    while (q < p->end && *q == '=')
        q++, level++;
    return q < p->end && *q == '[' ? level : -1;
}

// Reads [==[ ... ]==] (first newline dropped); returns its content
static const char *read_long(Parser *p, int level, size_t *len)
{
    p->s += level + 2;
    if (p->s < p->end && *p->s == '\r')
        p->s++;
    if (p->s < p->end && *p->s == '\n')
        p->s++, p->line++;
    const char *start = p->s;
    for (; p->s < p->end; p->s++)
    {
        if (*p->s == '\n')
        {
            p->line++;
            continue;
        }
        if (*p->s != ']')
            continue;
        const char *q = p->s + 1;
        int l = 0;
        while (q < p->end && *q == '=')
            q++, l++;
        if (l == level && q < p->end && *q == ']')
        {
            *len = (size_t)(p->s - start);
            p->s = q + 1;
            return start;
        }
    }
    fail(p, "unfinished long string or comment");
}

static void skip_space(Parser *p)
{
    while (p->s < p->end)
    {
        char c = *p->s;
        if (c == '\n')
            p->line++, p->s++;
        else if (is_space(c))
            p->s++;
        else if (c == '-' && p->s + 1 < p->end && p->s[1] == '-')
        {
            p->s += 2;
            int level = p->s < p->end && *p->s == '[' ? long_bracket(p) : -1;
            if (level >= 0)
            {
                size_t n;
                read_long(p, level, &n);
            }
            else
            {
                while (p->s < p->end && *p->s != '\n')
                    p->s++;
            }
        }
        else
            break;
    }
}

static void add_utf8(luaL_Buffer *b, unsigned long v)
{
    if (v < 0x80)
        luaL_addchar(b, (char)v);
    else if (v < 0x800)
    {
        luaL_addchar(b, (char)(0xC0 | (v >> 6)));
        luaL_addchar(b, (char)(0x80 | (v & 0x3F)));
    }
    else if (v < 0x10000)
    {
        luaL_addchar(b, (char)(0xE0 | (v >> 12)));
        luaL_addchar(b, (char)(0x80 | ((v >> 6) & 0x3F)));
        luaL_addchar(b, (char)(0x80 | (v & 0x3F)));
    }
    else
    {
        luaL_addchar(b, (char)(0xF0 | (v >> 18)));
        luaL_addchar(b, (char)(0x80 | ((v >> 12) & 0x3F)));
        luaL_addchar(b, (char)(0x80 | ((v >> 6) & 0x3F)));
        luaL_addchar(b, (char)(0x80 | (v & 0x3F)));
    }
}

// A quoted string with Lua escapes; pushes it
static void read_string(Parser *p)
{
    char quote = *p->s++;
    luaL_Buffer b;
    luaL_buffinit(p->L, &b);
    size_t n = 0;
    while (true)
    {
        if (p->s >= p->end || *p->s == '\n')
            fail(p, "unfinished string");
        char c = *p->s++;
        if (c == quote)
            break;
        if (++n > p->lim->max_string)
            fail(p, "string longer than %u bytes", (unsigned)p->lim->max_string);
        if (c != '\\')
        {
            luaL_addchar(&b, c);
            continue;
        }
        if (p->s >= p->end)
            fail(p, "unfinished string");
        c = *p->s++;
        switch (c)
        {
            case 'n': luaL_addchar(&b, '\n'); break;
            case 't': luaL_addchar(&b, '\t'); break;
            case 'r': luaL_addchar(&b, '\r'); break;
            case 'a': luaL_addchar(&b, '\a'); break;
            case 'b': luaL_addchar(&b, '\b'); break;
            case 'f': luaL_addchar(&b, '\f'); break;
            case 'v': luaL_addchar(&b, '\v'); break;
            case '\\': case '"': case '\'': luaL_addchar(&b, c); break;
            case '\n': p->line++; luaL_addchar(&b, '\n'); break;
            case 'x':
            {
                int h1 = p->s < p->end ? hex_value(p->s[0]) : -1;
                int h2 = p->s + 1 < p->end ? hex_value(p->s[1]) : -1;
                if (h1 < 0 || h2 < 0)
                    fail(p, "bad \\x escape");
                luaL_addchar(&b, (char)(h1 * 16 + h2));
                p->s += 2;
                break;
            }
            case 'z':
                while (p->s < p->end && is_space(*p->s))
                {
                    if (*p->s == '\n')
                        p->line++;
                    p->s++;
                }
                break;
            case 'u':
            {
                unsigned long v = 0;
                int digits = 0;
                if (p->s >= p->end || *p->s != '{')
                    fail(p, "bad \\u escape");
                p->s++;
                while (p->s < p->end && hex_value(*p->s) >= 0 && digits < 6)
                    v = v * 16 + (unsigned long)hex_value(*p->s++), digits++;
                if (digits == 0 || p->s >= p->end || *p->s != '}' || v > 0x10FFFF)
                    fail(p, "bad \\u escape");
                p->s++;
                add_utf8(&b, v);
                break;
            }
            default:
                if (!is_digit(c))
                    fail(p, "bad escape \\%c", c);
                int v = c - '0';
                for (int k = 0; k < 2 && p->s < p->end && is_digit(*p->s); k++)
                    v = v * 10 + (*p->s++ - '0');
                if (v > 255)
                    fail(p, "bad decimal escape");
                luaL_addchar(&b, (char)v);
        }
    }
    luaL_pushresult(&b);
}

// A number (decimal, hexadecimal, float); pushes it, negated if 'neg'
static void read_number(Parser *p, bool neg)
{
    char buf[64];
    size_t n = 0;
    while (p->s < p->end)
    {
        char c = *p->s;
        bool exp_sign = (c == '+' || c == '-') && n > 0
                        && (buf[n - 1] == 'e' || buf[n - 1] == 'E'
                            || buf[n - 1] == 'p' || buf[n - 1] == 'P');
        if (!is_name_char(c) && c != '.' && !exp_sign)
            break;
        if (n + 1 >= sizeof(buf))
            fail(p, "number too long");
        buf[n++] = c;
        p->s++;
    }
    buf[n] = '\0';
    if (lua_stringtonumber(p->L, buf) == 0)
        fail(p, "malformed number '%s'", buf);
    if (neg)
    {
        if (lua_isinteger(p->L, -1))
        {
            lua_Integer v = lua_tointeger(p->L, -1);
            lua_pop(p->L, 1);
            lua_pushinteger(p->L, (lua_Integer)(0u - (lua_Unsigned)v));
        }
        else
        {
            lua_Number v = lua_tonumber(p->L, -1);
            lua_pop(p->L, 1);
            lua_pushnumber(p->L, -v);
        }
    }
}

// A name at p->s: its length (0 if none)
static size_t name_len(const Parser *p)
{
    if (p->s >= p->end || !is_name_start(*p->s))
        return 0;
    const char *q = p->s;
    while (q < p->end && is_name_char(*q))
        q++;
    return (size_t)(q - p->s);
}

static bool is_word(const Parser *p, size_t len, const char *word)
{
    return len == strlen(word) && memcmp(p->s, word, len) == 0;
}

static void read_value(Parser *p, int depth);

// Fields of a table after '{'; pushes the table
static void read_table(Parser *p, int depth)
{
    if (depth > p->lim->max_depth)
        fail(p, "tables nested deeper than %d", p->lim->max_depth);
    luaL_checkstack(p->L, 8, "data nesting");
    lua_newtable(p->L);
    int table = lua_gettop(p->L);
    lua_Integer items = 0;
    bool fields = false;
    while (true)
    {
        skip_space(p);
        if (p->s >= p->end)
            fail(p, "'}' expected");
        if (*p->s == '}')
        {
            p->s++;
            break;
        }

        // Key: name = or ["string"] =
        bool keyed = false;
        size_t nl = name_len(p);
        if (nl && !is_word(p, nl, "true") && !is_word(p, nl, "false") && !is_word(p, nl, "nil"))
        {
            lua_pushlstring(p->L, p->s, nl);
            p->s += nl;
            skip_space(p);
            if (p->s >= p->end || *p->s != '=')
                fail(p, "'=' expected after '%s' (code is not allowed)", lua_tostring(p->L, -1));
            p->s++;
            keyed = true;
        }
        else if (*p->s == '[' && long_bracket(p) < 0)
        {
            p->s++;
            skip_space(p);
            if (p->s >= p->end || (*p->s != '"' && *p->s != '\''))
                fail(p, "only string keys are allowed: [\"name\"] = value");
            read_string(p);
            skip_space(p);
            if (p->s >= p->end || *p->s != ']')
                fail(p, "']' expected");
            p->s++;
            skip_space(p);
            if (p->s >= p->end || *p->s != '=')
                fail(p, "'=' expected");
            p->s++;
            keyed = true;
        }

        if (keyed)
        {
            lua_pushvalue(p->L, -1);
            if (lua_rawget(p->L, table) != LUA_TNIL)
                fail(p, "key '%s' appears twice", lua_tostring(p->L, -2));
            lua_pop(p->L, 1);
            read_value(p, depth);
            lua_rawset(p->L, table);
            fields = true;
        }
        else
        {
            read_value(p, depth);
            lua_rawseti(p->L, table, ++items);
        }
        if (fields && items)
            fail(p, "a table mixes list items and keyed fields");

        skip_space(p);
        if (p->s < p->end && (*p->s == ',' || *p->s == ';'))
            p->s++;
        else if (p->s >= p->end || *p->s != '}')
            fail(p, "',' or '}' expected");
    }
}

static void read_value(Parser *p, int depth)
{
    skip_space(p);
    if (p->s >= p->end)
        fail(p, "a value expected");
    char c = *p->s;
    if (c == '{')
    {
        p->s++;
        read_table(p, depth + 1);
    }
    else if (c == '"' || c == '\'')
        read_string(p);
    else if (c == '[' && long_bracket(p) >= 0)
    {
        size_t len;
        const char *t = read_long(p, long_bracket(p), &len);
        if (len > p->lim->max_string)
            fail(p, "string longer than %u bytes", (unsigned)p->lim->max_string);
        lua_pushlstring(p->L, t, len);
    }
    else if (is_digit(c) || (c == '.' && p->s + 1 < p->end && is_digit(p->s[1])))
        read_number(p, false);
    else if (c == '-')
    {
        p->s++;
        skip_space(p);
        if (p->s >= p->end || !(is_digit(*p->s) || *p->s == '.'))
            fail(p, "a number expected after '-'");
        read_number(p, true);
    }
    else
    {
        size_t nl = name_len(p);
        if (is_word(p, nl, "true") || is_word(p, nl, "false"))
        {
            lua_pushboolean(p->L, *p->s == 't');
            p->s += nl;
        }
        else if (is_word(p, nl, "nil"))
            fail(p, "nil is not allowed (leave the field out)");
        else if (nl)
            fail(p, "'%.*s' is not data (variables, calls and code are not allowed)",
                 (int)(nl > 32 ? 32 : nl), p->s);
        else
            fail(p, "unexpected character '%c'", c);
    }
}

static int parse_protected(lua_State *L)
{
    Parser *p = lua_touserdata(L, 1);
    lua_settop(L, 0);
    skip_space(p);
    size_t nl = name_len(p);
    if (!is_word(p, nl, "return"))
        fail(p, "the file must start with 'return' followed by a value");
    p->s += nl;
    read_value(p, 0);
    skip_space(p);
    if (p->s < p->end)
        fail(p, "only one value may follow 'return'");
    return 1;
}

bool ll_data_parse(lua_State *L, const char *text, size_t len, const char *name,
                   const LLDataLimits *limits, char *err, size_t err_size)
{
    if (len > limits->max_size)
    {
        snprintf(err, err_size, "%s: larger than %u KB", name,
                 (unsigned)(limits->max_size / 1024));
        return false;
    }
    if (len >= 3 && memcmp(text, "\xEF\xBB\xBF", 3) == 0) // UTF-8 BOM (Notepad)
        text += 3, len -= 3;

    Parser p = { text, text + len, 1, name, limits, L };
    lua_pushcfunction(L, parse_protected);
    lua_pushlightuserdata(L, &p);
    if (lua_pcall(L, 1, 1, 0) != LUA_OK)
    {
        const char *msg = lua_tostring(L, -1);
        snprintf(err, err_size, "%s", msg ? msg : "out of memory");
        lua_pop(L, 1);
        return false;
    }
    return true;
}
