// ff7_launcher_native.cpp - the macOS launcher's native helpers (SwiftUI calls these with
// @_silgen_name): what a mod is, as JSON, read with the game's own mod code (src/mods). The
// JSON is the one src/android/ff7_launcher_jni.cpp gives the Android launcher (same code).
#include <sys/stat.h>
#include <cstdio>
#include <string>
#include <vector>
#include "iro.hpp"
#include "modinfo.hpp"
#include "mods.h"
#include <cstdlib>
#include <mutex>
#include <cstdlib>
#include <cstring>
#include <mutex>

namespace {

std::string esc(const std::string &s) {
    std::string o;
    for (unsigned char c : s) {
        switch (c) {
        case '"': o += "\\\""; break;
        case '\\': o += "\\\\"; break;
        case '\n': o += "\\n"; break;
        case '\r': break;
        case '\t': o += "\\t"; break;
        default:
            if (c < 0x20) { char b[8]; std::snprintf(b, sizeof b, "\\u%04x", c); o += b; }
            else o += (char)c;
        }
    }
    return o;
}

std::string read_file(const std::string &p) {
    std::FILE *f = std::fopen(p.c_str(), "rb");
    if (!f) return std::string();
    std::string s;
    char buf[65536];
    size_t r;
    while ((r = std::fread(buf, 1, sizeof buf, f)) > 0) s.append(buf, r);
    std::fclose(f);
    return s;
}

std::string mod_json(const std::string &path) {
    using namespace ff7mods;
    std::string xml, err, kind;
    size_t files = 0;
    struct stat st;
    if (stat(path.c_str(), &st) != 0) return "{\"error\":\"not found\"}";
    if (st.st_mode & S_IFDIR) {
        kind = "folder";
        xml = read_file(path + "/mod.xml");
        if (xml.empty()) xml = read_file(path + "/Mod.xml");
    } else {
        kind = "iro";
        IroArchive a;
        if (!a.open(path)) return "{\"error\":\"" + esc(a.error()) + "\"}";
        files = a.entries().size();
        std::vector<uint8_t> v;
        if (a.read("mod.xml", v)) xml.assign(v.begin(), v.end());
    }
    if (xml.size() >= 3 && (uint8_t)xml[0] == 0xEF && (uint8_t)xml[1] == 0xBB && (uint8_t)xml[2] == 0xBF) xml.erase(0, 3);
    ModInfo m;
    bool has_xml = !xml.empty();
    if (has_xml && !parse_mod_xml(xml, m, err)) return "{\"error\":\"" + esc(err) + "\"}";
    std::string j = "{\"kind\":\"" + kind + "\",\"hasModXml\":" + (has_xml ? "true" : "false") +
                    ",\"files\":" + std::to_string(files) +
                    ",\"id\":\"" + esc(m.id) + "\",\"name\":\"" + esc(m.name) + "\",\"author\":\"" + esc(m.author) +
                    "\",\"version\":\"" + esc(m.version) + "\",\"category\":\"" + esc(m.category) +
                    "\",\"description\":\"" + esc(m.description) + "\",\"link\":\"" + esc(m.link) + "\",\"options\":[";
    for (size_t i = 0; i < m.options.size(); i++) {
        const ConfigOption &o = m.options[i];
        j += std::string(i ? "," : "") + "{\"id\":\"" + esc(o.id) + "\",\"name\":\"" + esc(o.name) + "\",\"type\":\"" +
             esc(o.type) + "\",\"default\":" + std::to_string(o.default_value) + ",\"description\":\"" + esc(o.description) +
             "\",\"values\":[";
        for (size_t k = 0; k < o.values.size(); k++)
            j += std::string(k ? "," : "") + "{\"value\":" + std::to_string(o.values[k].first) + ",\"name\":\"" + esc(o.values[k].second) + "\"}";
        j += "]}";
    }
    j += "],\"ffnx\":[";
    for (size_t i = 0; i < m.ffnx_config.size(); i++)
    {
        std::string when;
        if (i < m.ffnx_config_when.size())
            for (const auto &w : m.ffnx_config_when[i])
                when += (when.empty() ? "" : ";") + w.first + "=" + w.second;
        j += std::string(i ? "," : "") + "{\"key\":\"" + esc(m.ffnx_config[i].first) + "\",\"value\":\"" + esc(m.ffnx_config[i].second)
           + "\",\"when\":\"" + esc(when) + "\"}";
    }
    j += "],\"requires\":[";
    for (size_t i = 0; i < m.compat_requires.size(); i++)
        j += std::string(i ? "," : "") + "{\"id\":\"" + esc(m.compat_requires[i].mod_id) + "\",\"why\":\"" + esc(m.compat_requires[i].description) + "\"}";
    j += "],\"forbids\":[";
    for (size_t i = 0; i < m.compat_forbids.size(); i++)
        j += std::string(i ? "," : "") + "{\"id\":\"" + esc(m.compat_forbids[i].mod_id) + "\",\"why\":\"" + esc(m.compat_forbids[i].description) + "\"}";
    // <OrderConstraints>: the mods this one goes above / below (7th Heaven's auto-sort)
    j += "],\"before\":[";
    for (size_t i = 0; i < m.order_before.size(); i++) j += std::string(i ? "," : "") + "\"" + esc(m.order_before[i]) + "\"";
    j += "],\"after\":[";
    for (size_t i = 0; i < m.order_after.size(); i++) j += std::string(i ? "," : "") + "\"" + esc(m.order_after[i]) + "\"";
    j += "],\"unsupported\":[";
    for (size_t i = 0; i < m.windows_code.size(); i++) j += std::string(i ? "," : "") + "\"" + esc(m.windows_code[i]) + "\"";
    j += "]}";
    return j;
}

}  // namespace

static char *dup_str(const std::string &s) {
    char *p = static_cast<char *>(std::malloc(s.size() + 1));
    std::memcpy(p, s.c_str(), s.size() + 1);
    return p;
}

// {kind, hasModXml, id, name, author, version, category, description, link, options[], ffnx[], ...}
extern "C" char *ff7_launcher_mod_info(const char *path) { return dup_str(mod_json(path)); }

// mod.xml's preview image (or any file) from a mod folder or IRO archive, into out_path.
extern "C" int ff7_launcher_mod_file(const char *mod_path, const char *name, const char *out_path) {
    struct stat st;
    if (stat(mod_path, &st) != 0) return -1;
    std::vector<uint8_t> v;
    if (st.st_mode & S_IFDIR) {
        std::string p = std::string(mod_path) + "/" + name;
        for (char &c : p) if (c == '\\') c = '/';
        std::string s = read_file(p);
        if (s.empty()) return -1;
        v.assign(s.begin(), s.end());
    } else {
        ff7mods::IroArchive a;
        if (!a.open(mod_path) || !a.read(name, v)) return -1;
    }
    std::FILE *f = std::fopen(out_path, "wb");
    if (!f) return -1;
    std::fwrite(v.data(), 1, v.size(), f);
    std::fclose(f);
    return 0;
}

// The profile's conflicts (src/mods/mods.h ff7_mods_conflicts_json); "{}" if none.
static std::mutex g_overlay;
extern "C" char *ff7_launcher_conflicts(const char *profile) {
    std::lock_guard<std::mutex> lk(g_overlay);
    char *j = ff7_mods_conflicts_json(profile);
    return j ? j : dup_str("{}");
}

extern "C" void ff7_launcher_free(char *p) { std::free(p); }
