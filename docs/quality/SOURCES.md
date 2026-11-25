# Quality test photos - sources and licences

Downloaded in CI by `coreml/fetch_samples.py` from Wikimedia Commons (1600 px renditions), never committed in full. The preview JPEGs in this folder are reduced, degraded/processed derivatives used only to document model quality; each keeps the licence of its source (CC BY / CC BY-SA derivatives here are shared under the same licence, with the attribution below). `cat03` (GFDL) was used in CI only, no preview of it is committed.

| file | group | licence | author / credit | source page |
|---|---|---|---|---|
| color/president_barack_obama.jpg | colour | Public domain | Official White House Photo by Pete Souza | https://commons.wikimedia.org/wiki/File:President_Barack_Obama.jpg |
| color/official_portrait_of_barack_obama.jpg | colour | CC BY 3.0 | Pete Souza | https://commons.wikimedia.org/wiki/File:Official_portrait_of_Barack_Obama.jpg |
| color/neil_armstrong_pose.jpg | colour | Public domain | Unknown author | https://commons.wikimedia.org/wiki/File:Neil_Armstrong_pose.jpg |
| color/tunnel_view_yosemite_valley_yosemite_np_.jpg | colour | CC BY-SA 3.0 | Diliff | https://commons.wikimedia.org/wiki/File:Tunnel_View,_Yosemite_Valley,_Yosemite_NP_-_Diliff.jpg |
| color/cat03.jpg | colour | GFDL 1.2 | Fir0002 | https://commons.wikimedia.org/wiki/File:Cat03.jpg |
| color/felis_catus_cat_on_snow.jpg | colour | CC BY-SA 3.0 | Von.grzanka | https://commons.wikimedia.org/wiki/File:Felis_catus-cat_on_snow.jpg |
| bw/lange_migrantmother02.jpg | historical B&W | Public domain | Dorothea Lange | https://commons.wikimedia.org/wiki/File:Lange-MigrantMother02.jpg |
| bw/first_flight2.jpg | historical B&W | Public domain | John T. Daniels | https://commons.wikimedia.org/wiki/File:First_flight2.jpg |
| bw/abraham_lincoln_o_77_matte_collodion_pri.jpg | historical B&W | Public domain | Alexander Gardner | https://commons.wikimedia.org/wiki/File:Abraham_Lincoln_O-77_matte_collodion_print.jpg |

Degradations (synthetic, `coreml/degrade.py`): super-resolution input = Gaussian blur sigma 1.0-1.6, bicubic 1/4 downscale, Gaussian noise sigma 2-5, JPEG quality 55-75. Deblur input = linear motion blur 13-21 px at a random angle + noise sigma 1.5. Colorize input = CIE L* gray of the colour photo; historical photos are used as they are.
