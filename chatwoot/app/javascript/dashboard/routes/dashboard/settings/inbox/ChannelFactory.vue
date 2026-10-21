<script>
import { defineComponent, h } from 'vue';
import Facebook from './channels/Facebook.vue';
import Website from './channels/Website.vue';
import Twitter from './channels/Twitter.vue';
import Api from './channels/Api.vue';
import Email from './channels/Email.vue';
import Sms from './channels/Sms.vue';
import Whatsapp from './channels/Whatsapp.vue';
import WhatsappCall from './channels/WhatsappCall.vue';
import Line from './channels/Line.vue';
import Telegram from './channels/Telegram.vue';
import Instagram from './channels/Instagram.vue';
import Tiktok from './channels/Tiktok.vue';
import Voice from './channels/Voice.vue';
import Wapi from './channels/Wapi.vue';
import EvolutionApi from './channels/EvolutionApi.vue';
import ConnectChannelWizard from './channelConnect/ConnectChannelWizard.vue';

const channelViewList = {
  facebook: Facebook,
  website: Website,
  twitter: Twitter,
  api: Api,
  email: Email,
  sms: Sms,
  whatsapp: Whatsapp,
  whatsapp_call: WhatsappCall,
  line: Line,
  telegram: Telegram,
  instagram: Instagram,
  tiktok: Tiktok,
  voice: Voice,
  wapi: Wapi,
  evolution_api: EvolutionApi,
};

// Canais nao oficiais: assistente "Conectar canal" (login por usuario/senha ou QR).
const unofficialProviders = {
  instagram_unofficial: 'instagram',
  facebook_unofficial: 'messenger',
  tiktok_unofficial: 'tiktok',
  whatsapp_unofficial: 'whatsapp',
};

export default defineComponent({
  name: 'NewChannelView',
  props: {
    channelName: {
      type: String,
      required: true,
    },
  },
  render() {
    const provider = unofficialProviders[this.channelName];
    if (provider) return h(ConnectChannelWizard, { provider });
    const ChannelComponent = channelViewList[this.channelName];
    return ChannelComponent ? h(ChannelComponent) : null;
  },
});
</script>
