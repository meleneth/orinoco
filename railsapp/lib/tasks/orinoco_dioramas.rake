namespace :orinoco do
  namespace :dioramas do
    desc "Create the default clip show diorama"
    task create_clip_show_default: :environment do
      diorama = Dioramas::Defaults::ClipShow.create!

      puts "Created diorama #{diorama.slug} (#{diorama.id})"
    end
  end
end
