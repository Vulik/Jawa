import discord
from discord import app_commands, Embed, Colour, ui
from discord.ext import commands, tasks
import asyncio
import json
import os
import aiohttp
import logging
from datetime import datetime
from typing import Dict, Optional, List, Tuple
import pytz
import io
import zipfile

# ========== KONFIGURASI ==========
BOT_PREFIX = "!"
CONFIG_FILE = "config.json"
TOKENS_FILE = "tokens.json"
OWNER_ID = 00   # GANTI DENGAN ID ANDA
DELAY_MARGIN = 5                 # detik tambahan setelah retry_after
DEFAULT_DELAY = 1800            # 30 menit
MAX_ERROR_COUNT = 5            # hapus channel setelah 5x error berturut-turut
TIMEZONE = "Asia/Jakarta"

# ========== LOGGING ==========
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('discord_bot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# ========== LOAD / SAVE CONFIG ==========
def load_config():
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    return {"default_delay": DEFAULT_DELAY}

def save_config(config):
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=2)

def load_tokens():
    if os.path.exists(TOKENS_FILE):
        with open(TOKENS_FILE, 'r') as f:
            data = json.load(f)
            # Migrasi format lama (list of strings) ke objek
            if "tokens" in data and data["tokens"] and isinstance(data["tokens"][0], str):
                new_tokens = []
                for token in data["tokens"]:
                    new_tokens.append({
                        "token": token,
                        "user_id": "unknown",
                        "username": "Unknown",
                        "active": False,
                        "strict": False,
                        "token_default_message": None,
                        "channels": [],
                        "schedule": {
                            "enabled": False,
                            "start": "08:00",
                            "end": "22:00"
                        },
                        "added_at": datetime.now().isoformat()
                    })
                data["tokens"] = new_tokens
                save_tokens(data)
            else:
                # Migrasi field schedule, strict, stats, consecutive_errors
                for t in data.get("tokens", []):
                    if "schedule" not in t:
                        t["schedule"] = {"enabled": False, "start": "08:00", "end": "22:00"}
                    if "strict" not in t:
                        t["strict"] = False
                    for ch in t.get("channels", []):
                        if "stats" not in ch:
                            ch["stats"] = {"messages_sent": 0, "messages_failed": 0}
                        if "consecutive_errors" not in ch:
                            ch["consecutive_errors"] = 0
                save_tokens(data)
            return data
    return {"tokens": []}

def save_tokens(tokens_config):
    with open(TOKENS_FILE, 'w') as f:
        json.dump(tokens_config, f, indent=2)

config = load_config()
tokens_config = load_tokens()

# ========== CHANNEL MANAGER (PER TOKEN) ==========
class ChannelManager:
    def __init__(self):
        self.active_tasks = {}   # key: f"{token_index}:{channel_id}"

    async def send_discord_message(self, token: str, channel_id: str, content: str) -> Tuple[bool, Optional[float]]:
        """Kirim pesan ke channel. Return: (success, retry_after)"""
        if not content or not content.strip():
            logger.warning(f"Empty message, skipping send to {channel_id}")
            return False, None

        try:
            headers = {
                "Authorization": token,
                "Content-Type": "application/json",
                "User-Agent": "Mozilla/5.0"
            }
            payload = {"content": content}
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"https://discord.com/api/v10/channels/{channel_id}/messages",
                    headers=headers,
                    json=payload
                ) as response:
                    if response.status == 429:
                        data = await response.json()
                        retry_after = data.get("retry_after", 5)
                        logger.warning(f"Rate limited. Retry after {retry_after}s")
                        return False, float(retry_after)
                    if response.status in (200, 201, 204):
                        logger.info(f"Message sent to {channel_id}")
                        return True, None
                    else:
                        error_text = await response.text()
                        logger.error(f"Failed to send message: {response.status} - {error_text}")
                        return False, None
        except Exception as e:
            logger.error(f"Error sending message: {e}")
            return False, None

    async def start_channel_task(self, token_index: int, token_obj: dict, channel_id: str):
        """Memulai loop pengiriman untuk satu channel"""
        task_key = f"{token_index}:{channel_id}"
        if task_key in self.active_tasks:
            return False

        # Cari data channel
        channel_data = None
        for ch in token_obj.get("channels", []):
            if ch["channel_id"] == channel_id:
                channel_data = ch
                break
        if not channel_data:
            return False

        delay = channel_data.get("delay", config["default_delay"])

        # Tentukan pesan
        if token_obj.get("strict", False):
            message = token_obj.get("token_default_message") or ""
        else:
            message = channel_data.get("custom_message") or token_obj.get("token_default_message") or ""

        async def channel_loop():
            nonlocal delay
            logger.info(f"Starting loop for token {token_index}, channel {channel_id}")
            while task_key in self.active_tasks:
                try:
                    # Cek apakah pesan kosong
                    if not message or not message.strip():
                        logger.warning(f"Message is empty for channel {channel_id}, skipping send")
                        await asyncio.sleep(delay)
                        continue

                    success, retry_after = await self.send_discord_message(
                        token_obj["token"], channel_id, message
                    )

                    if success:
                        # Update statistik
                        channel_data["stats"]["messages_sent"] = channel_data["stats"].get("messages_sent", 0) + 1
                        channel_data["consecutive_errors"] = 0
                        channel_data["last_sent"] = datetime.now().isoformat()
                        save_tokens(tokens_config)
                        await asyncio.sleep(delay)
                    else:
                        # Update statistik gagal
                        channel_data["stats"]["messages_failed"] = channel_data["stats"].get("messages_failed", 0) + 1
                        channel_data["consecutive_errors"] = channel_data.get("consecutive_errors", 0) + 1
                        save_tokens(tokens_config)

                        if retry_after is not None:
                            # Rate limit – update delay
                            new_delay = retry_after + DELAY_MARGIN
                            logger.info(f"Updating delay for channel {channel_id}: {delay} -> {new_delay}s")
                            channel_data["delay"] = new_delay
                            save_tokens(tokens_config)
                            delay = new_delay
                            await asyncio.sleep(retry_after)
                        else:
                            # Error permanen – cek apakah sudah melebihi batas
                            if channel_data.get("consecutive_errors", 0) >= MAX_ERROR_COUNT:
                                logger.warning(f"Channel {channel_id} has {MAX_ERROR_COUNT} consecutive errors, auto-removing")
                                # Hapus channel
                                token_obj["channels"] = [c for c in token_obj["channels"] if c["channel_id"] != channel_id]
                                save_tokens(tokens_config)
                                await self.stop_channel_task(token_index, channel_id, auto=True)
                                break
                            else:
                                # Matikan channel tapi tetap simpan
                                logger.warning(f"Permanent failure for channel {channel_id}, deactivating")
                                await self.stop_channel_task(token_index, channel_id, auto=True)
                                break
                except Exception as e:
                    logger.error(f"Error in channel loop {channel_id}: {e}")
                    await asyncio.sleep(60)

        task = asyncio.create_task(channel_loop())
        self.active_tasks[task_key] = task
        channel_data["active"] = True
        save_tokens(tokens_config)
        return True

    async def stop_channel_task(self, token_index: int, channel_id: str, auto: bool = False):
        """Menghentikan loop channel"""
        task_key = f"{token_index}:{channel_id}"
        if task_key in self.active_tasks:
            self.active_tasks[task_key].cancel()
            try:
                await self.active_tasks[task_key]
            except asyncio.CancelledError:
                pass
            del self.active_tasks[task_key]

            token_obj = tokens_config["tokens"][token_index]
            for ch in token_obj.get("channels", []):
                if ch["channel_id"] == channel_id:
                    ch["active"] = False
                    if auto:
                        ch["last_error"] = datetime.now().isoformat()
                    save_tokens(tokens_config)
                    break
            return True
        return False

    async def restart_channel_task(self, token_index: int, token_obj: dict, channel_id: str):
        await self.stop_channel_task(token_index, channel_id)
        await asyncio.sleep(1)
        return await self.start_channel_task(token_index, token_obj, channel_id)

    async def start_all_token_channels(self, token_index: int, token_obj: dict):
        """Mulai semua channel yang tidak memiliki last_error"""
        for ch in token_obj.get("channels", []):
            if ch.get("last_error") is None and ch["channel_id"] not in self.active_tasks:
                ch["active"] = True
                save_tokens(tokens_config)
                await self.start_channel_task(token_index, token_obj, ch["channel_id"])

    async def stop_all_token_channels(self, token_index: int, token_obj: dict):
        """Hentikan semua channel token ini"""
        for ch in token_obj.get("channels", []):
            await self.stop_channel_task(token_index, ch["channel_id"])

channel_manager = ChannelManager()

# ========== AUTO-REFRESH DASHBOARD ==========
class DashboardManager:
    def __init__(self):
        self.active_dashboards = {}  # user_id -> (channel_id, message_id, view)
        self.refresh_task = None

    def add_dashboard(self, user_id: int, channel_id: int, message_id: int, view: ui.View):
        self.active_dashboards[user_id] = (channel_id, message_id, view)
        if self.refresh_task is None or self.refresh_task.done():
            self.refresh_task = asyncio.create_task(self._auto_refresh_loop())

    def remove_dashboard(self, user_id: int):
        if user_id in self.active_dashboards:
            del self.active_dashboards[user_id]

    async def _auto_refresh_loop(self):
        await asyncio.sleep(5)
        while self.active_dashboards:
            for user_id, (ch_id, msg_id, view) in list(self.active_dashboards.items()):
                try:
                    channel = bot.get_channel(ch_id) or await bot.fetch_channel(ch_id)
                    message = await channel.fetch_message(msg_id)
                    embed = build_main_dashboard_embed()
                    await message.edit(embed=embed, view=view)
                except (discord.NotFound, discord.Forbidden):
                    self.remove_dashboard(user_id)
                except Exception as e:
                    logger.error(f"Auto-refresh error for user {user_id}: {e}")
                    self.remove_dashboard(user_id)
            await asyncio.sleep(5)

dashboard_manager = DashboardManager()

# ========== SCHEDULED ON/OFF ==========
@tasks.loop(minutes=1)
async def check_schedules():
    """Cek jadwal setiap token dan aktifkan/nonaktifkan otomatis"""
    tz = pytz.timezone(TIMEZONE)
    now = datetime.now(tz)
    current_time = now.strftime("%H:%M")

    for idx, token_obj in enumerate(tokens_config.get("tokens", [])):
        schedule = token_obj.get("schedule", {})
        if not schedule.get("enabled"):
            continue
        start = schedule.get("start", "08:00")
        end = schedule.get("end", "22:00")

        should_be_on = False
        if start <= end:
            should_be_on = start <= current_time <= end
        else:  # melewati tengah malam
            should_be_on = current_time >= start or current_time <= end

        if should_be_on and not token_obj.get("active"):
            token_obj["active"] = True
            for ch in token_obj.get("channels", []):
                if ch.get("last_error") is None:
                    ch["active"] = True
            save_tokens(tokens_config)
            await channel_manager.start_all_token_channels(idx, token_obj)
            logger.info(f"Schedule turned ON token {token_obj.get('username')}")
        elif not should_be_on and token_obj.get("active"):
            token_obj["active"] = False
            for ch in token_obj.get("channels", []):
                ch["active"] = False
            save_tokens(tokens_config)
            await channel_manager.stop_all_token_channels(idx, token_obj)
            logger.info(f"Schedule turned OFF token {token_obj.get('username')}")

# ========== INTENTS & BOT ==========
intents = discord.Intents.default()
intents.message_content = True

class MyBot(commands.Bot):
    def __init__(self):
        super().__init__(command_prefix=BOT_PREFIX, intents=intents, help_command=None)

    async def setup_hook(self):
        await self.tree.sync()
        logger.info("Slash commands synced")
        check_schedules.start()

bot = MyBot()

# ========== HELPER EMBEDS ==========
def success_embed(title: str, desc: str = "") -> Embed:
    return Embed(title=title, description=desc, colour=Colour.green())
def error_embed(title: str, desc: str = "") -> Embed:
    return Embed(title=title, description=desc, colour=Colour.red())
def warning_embed(title: str, desc: str = "") -> Embed:
    return Embed(title=title, description=desc, colour=Colour.orange())
def info_embed(title: str, desc: str = "") -> Embed:
    return Embed(title=title, description=desc, colour=Colour.blue())

# ========== OWNER CHECK ==========
def owner_only():
    async def predicate(interaction: discord.Interaction):
        if interaction.user.id != OWNER_ID:
            await interaction.response.send_message(
                embed=error_embed("⛔ Akses Ditolak", f"Hanya <@{OWNER_ID}> yang dapat menggunakan perintah ini."),
                ephemeral=True
            )
            return False
        return True
    return app_commands.check(predicate)

# ========== FUNGSI BANTU AMBIL INFO TOKEN ==========
async def fetch_token_info(token: str) -> Tuple[Optional[str], Optional[str]]:
    """Mengambil user ID dan username dari token"""
    try:
        headers = {"Authorization": token, "User-Agent": "Mozilla/5.0"}
        async with aiohttp.ClientSession() as session:
            async with session.get("https://discord.com/api/v10/users/@me", headers=headers) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    user_id = data["id"]
                    username = data["username"] + "#" + data["discriminator"] if data.get("discriminator") != "0" else data["username"]
                    return user_id, username
                else:
                    return None, None
    except:
        return None, None

# ========== DASHBOARD UTAMA ==========
def build_main_dashboard_embed() -> Embed:
    embed = Embed(
        title="📊 Discord Auto Dashboard",
        description="Daftar token pengirim pesan",
        colour=Colour.blue()
    )
    if not tokens_config["tokens"]:
        embed.description = "Belum ada token. Gunakan tombol **Add Token**."
        return embed

    for idx, tok in enumerate(tokens_config["tokens"]):
        status = "🟢 Online" if tok.get("active", False) else "🔴 Offline"
        mode = "Strict" if tok.get("strict", False) else "Non‑strict"
        ch_count = len(tok.get("channels", []))
        active_ch = sum(1 for ch in tok.get("channels", []) if ch.get("active", False))
        name = tok.get("username", "Unknown")
        user_id = tok.get("user_id", "?")
        owner_mention = f"<@{user_id}>" if user_id != "?" and user_id != "unknown" else "`?`"
        schedule = tok.get("schedule", {})
        sched_icon = "⏰" if schedule.get("enabled") else ""
        embed.add_field(
            name=f"[ {name} ] {sched_icon}",
            value=f"Owner: {owner_mention}\nChannels: {active_ch}/{ch_count}\nStatus: {status}\nMode: {mode}",
            inline=True
        )
    
    # Footer dengan waktu refresh
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    embed.set_footer(text=f"Auto-refresh setiap 5 detik • Terakhir: {now}")
    return embed

class MainDashboardView(ui.View):
    def __init__(self):
        super().__init__(timeout=None)  # persistent view

    async def interaction_check(self, interaction: discord.Interaction) -> bool:
        if interaction.user.id != OWNER_ID:
            await interaction.response.send_message(embed=error_embed("⛔ Owner Only"), ephemeral=True)
            return False
        return True

    @ui.button(label="➕ Add Token", style=discord.ButtonStyle.success)
    async def add_token(self, interaction: discord.Interaction, button: ui.Button):
        dashboard_manager.remove_dashboard(interaction.user.id)
        modal = AddTokenModal()
        await interaction.response.send_modal(modal)

    @ui.button(label="❌ Remove Token", style=discord.ButtonStyle.danger)
    async def remove_token(self, interaction: discord.Interaction, button: ui.Button):
        if not tokens_config["tokens"]:
            await interaction.response.send_message(embed=warning_embed("⚠️ Tidak ada token"), ephemeral=True)
            return
        dashboard_manager.remove_dashboard(interaction.user.id)
        view = RemoveTokenView()
        embed = info_embed("🗑 Pilih Token yang akan dihapus")
        await interaction.response.send_message(embed=embed, view=view, ephemeral=True)

    @ui.button(label="🔍 Select Token", style=discord.ButtonStyle.primary)
    async def select_token(self, interaction: discord.Interaction, button: ui.Button):
        if not tokens_config["tokens"]:
            await interaction.response.send_message(embed=warning_embed("⚠️ Tidak ada token"), ephemeral=True)
            return
        dashboard_manager.remove_dashboard(interaction.user.id)
        view = TokenSelectView()
        embed = info_embed("🔽 Pilih Token untuk dikelola")
        await interaction.response.send_message(embed=embed, view=view, ephemeral=True)

    @ui.button(label="🔴 EMERGENCY STOP", style=discord.ButtonStyle.danger, row=1)
    async def emergency_stop(self, interaction: discord.Interaction, button: ui.Button):
        # Hapus dashboard dari auto-refresh sementara
        dashboard_manager.